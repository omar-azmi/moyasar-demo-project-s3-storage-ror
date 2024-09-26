require "async"
require "rake"
require "net/http"
require "uri"
require "./lib/helpers/async_promise"
require "./lib/helpers/s3_signer"
require "./lib/helpers/fetch"
require_relative "./base"

# Configuration for S3 backend socket
#
# @param host [String] host the domain name or host name of the minio server, not including the http uri scheme.
#        for instance, for the url "http://localhost:9000/default/temp/hello_world.txt", the host is `"localhost:9000"`.
#
# @param bucket [String] the name of the minio bucket that you shall be using.
#        do not include leading or trailing slashes in its name.
#
# @param access_key [String] a valid access key (or username) to access your bucket.
#        for a vanilla minio setup, you may use the default `"minioadmin"` username.
#        to create additional accessKey-secretKey pairs, you can:
#        - visit the minio webui portal (`http://localhost:9001`)
#        - navigate to `Access Keys` on the left pane.
#        - click the `Create access key` button on the top-right.
#        - copy the `Access Key` and `Secret Key`, and use them for this configuration.
#        - click on the `Create` button.
#
# @param secret_key [String] a valid secret key (or password) to access your bucket.
#        for a vanilla minio setup, you may use the default `"minioadmin"` password.
#        to generate a new accessKey-secretKey pair, see the comment in {@link access_key}.
#
# @param timeout [Float] the number of seconds to wait before declaring a timeout.
S3BackendSocketConfig = Struct.new(:host, :bucket, :access_key, :secret_key, :timeout)

# Default S3 backend configuration
DEFAULT_S3_CONFIG = S3BackendSocketConfig.new(
  "localhost:9000",
  "s3-bucket",
  "minioadmin",
  "minioadmin",
  5.0,
)

# A module for managing the state of minio server more conveniently.
module MinIO
  extend self

  @rake = Rake.application()
  @rake.init()
  @rake.load_rakefile()

  # bootup minio server (via rake task) with default settings
  # @return [AsyncPromise<true>]
  def bootup
    AsyncPromise.resolve().then(->(_) {
      # we call `execute` instead of `invoke` because the same task cannot be run again it is `invoke`d (but `execute` does allow for that)
      @rake["minio:start"].execute()
      sleep(3)
    })
  end

  # shutdown minio server (via rake task)
  # @return [AsyncPromise<true>]
  def shutdown
    AsyncPromise.resolve().then(->(_) {
      # we call `execute` instead of `invoke` because the same task cannot be run again it is `invoke`d (but `execute` does allow for that)
      @rake["minio:close"].execute()
      sleep(2)
    })
  end

  # Checks if a Minio bucket is online and available, by sending a HEAD request, and returns [true] if it was successful,
  # or returns a [false] if your request was bad (http 400 or 300 response).
  # @raise [BackendNetworkError] if there is a TCP connection error with the host (i.e. backend server failed to perform http handshake)
  # @param config [S3BackendSocketConfig]
  # @return [AsyncPromise<Boolean>]
  def is_bucket_available(config = DEFAULT_S3_CONFIG)
    # similar to object destructuring in javascript
    config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "HEAD", headers: { "x-amz-expected-bucket-owner" => access_key })
    url = "http://#{host}#{pathname}"
    # @type [AsyncPromise<Boolean>]
    promise = AsyncPromise.resolve().then(->(_) {
      uri = URI.parse(url)
      response = nil
      begin
        # initiate the http request
        response = async_fetch(url, method: "HEAD", headers: headers, timeout: timeout).wait

      # Rename connection refused error (i.e. closed-host or if the service is down)
      rescue Errno::ECONNREFUSED, SocketError => details
        raise BackendNetworkError.new("TCP connection refused by Minio S3 host: #{uri.host}.")
      # Rename network connection timeout error
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => details
        raise BackendNetworkError.new("Connection timed out with Minio S3 host: #{uri.host} after #{timeout} seconds.")
      # Rename other standard errors
      rescue StandardError => details
        raise BackendNetworkError.new("Unidentified standard error when connecting to Minio S3 host: #{uri.host}.")

      else
        # Return whether or not the response's status was successful
        # If it is [false], then your Minio S3 bucket is online, but your credentials are incorrect.
        response.is_a?(Net::HTTPSuccess)
      end
    })
    promise
  end
end


# S3BackendSocket class inherits from StorageBackendSocket
class S3BackendSocket < StorageBackendSocket
  # attr_accessor :is_ready # inherited

  # @param config [S3BackendSocketConfig] the config for communicating with our minio server's bucket
  def initialize(config = {})
    super()
    config = config.is_a?(S3BackendSocketConfig) ? config.to_h() : config
    # @type [S3BackendSocketConfig]
    @config = DEFAULT_S3_CONFIG.to_h.merge(config)
    # @type [AsyncPromise<true>]
    @is_ready = AsyncPromise.new()
    self.init()
  end

  # Initializes the minio backend server, and flicks `is_ready` promise to a resolved state when server booting is successful.
  # @return [AsyncPromise<void>]
  def init
    @is_ready = AsyncPromise.new()
    AsyncPromise.resolve().then(->(_) {
      begin
        MinIO.bootup().wait
        MinIO.is_bucket_available(@config).wait
        @is_ready.resolve(true)
      rescue StandardError => reason
        @is_ready.reject(BackendNetworkError.new("Failed to initialize: #{reason.message}"))
      end
    })
  end

  # No operation needed for for backups, since minio handles it itself
  # @return [AsyncPromise<void>]
  def backup
    AsyncPromise.resolve()
  end

  # Closes the minio backend server
  # @return [AsyncPromise<void>]
  def close
    AsyncPromise.resolve().then(->(_) {
      @is_ready = AsyncPromise.reject("MinIO server has been shut down.")
      MinIO.shutdown().wait
    })
  end

  # Checks if the minio backend server is online, and returns a promise for the latency in  milliseconds
  # @return [AsyncPromise<nil, Float>]
  def is_online
    AsyncPromise.resolve()
      .then(->(_) {
        is_ready.wait
        delta_time = Time.now
        bucket_is_online = MinIO.is_bucket_available(@config).wait
        delta_time = Time.now - delta_time
        bucket_is_online \
          ? delta_time * 1000 # latency in milliseconds
          : nil
      })
      .catch(->(reason) { nil })
  end

  # Retrieves object metadata by its ID
  # @return [AsyncPromise<StorageObjectMetadata>]
  def get_object_metadata(id)
    @config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}/#{id}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "GET", query: "attributes=", headers: { "x-amz-object-attributes" => "ObjectSize" })
    url = "http://#{host}#{pathname}?attributes"

    AsyncPromise.race([
      AsyncPromise.timeout(nil, timeout, reject: "Timeout when retrieve metadata for object #{id}"),
      is_ready.then(->(backend_available) {
        unless backend_available == true
          raise BackendNetworkError, "Backend can connect, but is not available for requests (possibly wrong url?). Failed to retrieve metadata for object #{id}"
        end
        response = async_fetch(url, method: "GET", headers: headers, timeout: timeout).wait
        unless response.is_a?(Net::HTTPSuccess)
          raise BackendNetworkError, "Failed to retrieve metadata for object #{id}"
        end
        # extract object size and creation date from xml response body
        size = response.body.match(/<ObjectSize>(\d+)<\/ObjectSize>/)[1].to_i
        last_modified = response["last-modified"]
        created_at = Time.parse(last_modified).to_i * 1000
        { id: id, size: size, created_at: created_at }
      })
    ])
  end

  # Checks if the backend approves storing the object based on metadata
  def approve_object_metadata(stats)
    stats => {id:, size:}
    @config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}/#{id}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "HEAD")
    url = "http://#{host}#{pathname}"

    AsyncPromise.race([
      AsyncPromise.timeout(nil, timeout, reject: "Timeout when approving metadata for object #{id}"),
      is_ready.then(->(backend_available) {
        unless backend_available == true
          raise BackendNetworkError, "Backend can connect, but is not available for requests (possibly wrong url?). Failed to retrieve metadata for object #{id}"
        end
        response = async_fetch(url, method: "HEAD", headers: headers, timeout: timeout).wait
        # Object already exists if HEAD response is OK
        if response.is_a?(Net::HTTPSuccess)
          raise BackendNetworkError, "The blob with the id \"#{id}\" already exists."
        end
        true
      })
    ])
  end

  # Retrieves an object blob from the backend by its ID
  def get_object(id)
    @config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}/#{id}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "GET")
    url = "http://#{host}#{pathname}"
    is_ready.then(->(backend_available) {
      unless backend_available == true
        raise BackendNetworkError, "Backend can connect, but is not available for requests (possibly wrong url?). Failed to retrieve metadata for object #{id}"
      end
      response = async_fetch(url, method: "GET", headers: headers, timeout: timeout).wait
      unless response.is_a?(Net::HTTPSuccess)
        raise BackendNetworkError, "Failed to retrieve object #{id}"
      end
      response.body # returning the raw body (blob)
    })
  end

  # Stores an object blob in the backend by its ID
  def set_object(id, data)
    @config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}/#{id}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "PUT")
    url = "http://#{host}#{pathname}"
    is_ready.then(->(backend_available) {
      unless backend_available == true
        raise BackendNetworkError, "Backend can connect, but is not available for requests (possibly wrong url?). Failed to retrieve metadata for object #{id}"
      end
      response = async_fetch(url, method: "PUT", body: data, headers: headers, timeout: timeout).wait
      unless response.is_a?(Net::HTTPSuccess)
        raise BackendNetworkError, "Failed to store object #{id}"
      end
      get_object_metadata(id).wait # return metadata after storing the object
    })
  end

  # Deletes an object blob in the backend by its ID
  # used only for testing purposes
  # @return [AsyncPromise<Boolean>] The promise specifies whether or not the item existed before deleting
  # TODO: for now, there is no distinction between non-existing deleted item vs existing item's deletion
  def del_object(id)
    @config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}/#{id}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "DELETE")
    url = "http://#{host}#{pathname}"
    is_ready.then(->(backend_available) {
      unless backend_available == true
        raise BackendNetworkError, "Backend can connect, but is not available for requests (possibly wrong url?). Failed to retrieve metadata for object #{id}"
      end
      response = async_fetch(url, method: "DELETE", headers: headers, timeout: timeout).wait
      return true if response.code == "204"
      unless response.is_a?(Net::HTTPSuccess)
        raise BackendNetworkError, "Failed to carry out delete operation on object #{id}"
      end
    })
  end
end
