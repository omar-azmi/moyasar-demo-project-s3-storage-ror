require "async"
require "async"
require "rake"
require "net/http"
require "uri"
require "./lib/helpers/async_promise"
require "./lib/helpers/s3_signer"
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
    bucket_uri = URI.parse("http://#{host}#{pathname}")
    # @type [AsyncPromise<Boolean>]
    promise = AsyncPromise.resolve(bucket_uri).then(->(uri) {
      response = nil
      begin
        # initiate the HTTP request
        response = Net::HTTP.start(uri.host, uri.port, open_timeout: timeout, read_timeout: 5) do |http|
          request = Net::HTTP::Head.new(uri)
          headers.each { |key, value| request[key] = value }
          http.request(request)
        end

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
