require "async"
require "async/clock"
require "net/http"
require "uri"
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

# Checks if a Minio bucket is online and available, by sending a HEAD request, and returns [true] if it was successful,
# or returns a [false] if your request was bad (http 400 or 300 response).
# @raise [BackendNetworkError] if there is a TCP connection error with the host (i.e. backend server failed to perform http handshake)
# @param config [S3BackendSocketConfig]
# @return [Async::Task<Boolean>]
def is_minio_bucket_available(config = DEFAULT_S3_CONFIG)
  Async do
    # similar to object destructuring in javascript
    config => {host:, bucket:, access_key:, secret_key:, timeout:}
    pathname = "/#{bucket}"
    headers = S3Signer.get_signed_headers(host, pathname, access_key, secret_key, method: "HEAD", headers: { "x-amz-expected-bucket-owner" => access_key })
    uri = URI.parse("http://#{host}#{pathname}")

    # setting our connecting timeout bsed on our configuration
    response = nil
    begin
      # initiate the HTTP request
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: timeout, read_timeout: 5) do |http|
        request = Net::HTTP::Head.new(uri)
        headers.each { |key, value| request[key] = value }
        http.request(request)
      end

    # The `.tap { |e| e.set_backtrace(nil) }` calls below make the error stack trace shorter, focusing only on the error that you raise, and not that of the origin

    # Handle connection refused (i.e. closed-host or if the service is down)
    rescue Errno::ECONNREFUSED, SocketError => details
      raise BackendNetworkError.new("TCP connection refused by Minio S3 host: #{uri.host}.").tap { |e| e.set_backtrace(nil) }

    # Handle network connection timeout
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => details
      raise BackendNetworkError.new("Connection timed out with Minio S3 host: #{uri.host} after #{timeout} seconds.").tap { |e| e.set_backtrace(nil) }

    # Handle other standard errors
    rescue StandardError => details
      raise BackendNetworkError.new("Unidentified standard error when connecting to Minio S3 host: #{uri.host}.").tap { |e| e.set_backtrace(nil) }
    end

    # Return whether or not the response's status was successful
    # If it is [false], then your Minio S3 bucket is online, but your credentials are incorrect.
    response.is_a?(Net::HTTPSuccess)
  end
end
