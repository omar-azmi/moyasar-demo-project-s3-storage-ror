
require "openssl"
require "time"
require "uri"
require_relative "./crypto"

module S3Signer
  include CryptoHelper

  AWS4_REQUEST_SCOPE = "aws4_request"

  # Normalize and format an http header object (hash map) as a canonical header string.
  # This process is needed when building the full canonical request string, since the http headers are part of it.
  # The following actions take place in order to make it read out just like the header string that is sent out by a browser:
  # - the entries are sorted alphabetically by the key's name
  # - the keys are lowered in their casing
  # - the values have their leading and trailing empty spaces trimmed
  #
  # @param headers [Hash] The http headers to normalize
  # @return [String] Normalized and formatted http headers
  def http_headers_to_string(headers)
    normalized_headers = headers
      .transform_keys(&:downcase)
      .transform_values(&:strip)
    sorted_keys = normalized_headers.keys.sort
    sorted_keys.map { |key| "#{key}:#{normalized_headers[key]}" }.join("\n")
  end

  # Get the keys of http headers in sorted order
  # @param headers [Hash] The http headers object
  # @return [Array<String>] Sorted list of header keys
  def get_http_header_keys(headers)
    headers.keys.map(&:downcase).sort
  end

  # Compute AWS Signature V4 signed headers
  # @param host [String] The domain name or host name of the server, without the scheme
  # @param pathname [String] The path to the resource
  # @param access_key [String] A valid S3 bucket owner's access key
  # @param secret_key [String] The same owner's valid S3 bucket secret key
  # @param config [Hash] Additional configuration for signing
  # @return [Hash] Signed headers including the "Authorization" field
  def get_signed_headers(host, pathname, access_key, secret_key, config = {})
    # Default configuration
    config = {
      query: "",
      headers: {},
      date: Time.now.utc.iso8601.gsub(/[:-]|\.\d{3}/, ""), # e.g. "20240920T000000Z"
      service: "s3",
      payload: { unsigned: true },
      method: "GET",
      region: "us-east-1"
    }.merge(config)

    config[:method] = config[:method].upcase
    amz_date = config[:date]
    date_stamp = amz_date[0, 8] # extract date in yyyymmdd format

    payload_hash = case config[:payload]
    when String
      buffer_to_hexstring(sha256(config[:payload]))
    when Hash
      config[:payload][:sha256] || "UNSIGNED-PAYLOAD"
    else
      "UNSIGNED-PAYLOAD"
    end

    canonical_headers = {
      "host" => host,
      "x-amz-date" => amz_date,
      "x-amz-content-sha256" => payload_hash
    }.merge(config[:headers])

    # Step 1: Generate the canonical request
    signed_headers = get_http_header_keys(canonical_headers).join(";") # e.g. "host;range;x-amz-content-sha256;x-amz-date"
    canonical_request = [
      config[:method],               # http method
      pathname,                      # pathname
      config[:query],                # query parameters
      http_headers_to_string(canonical_headers), # canonical headers
      "",                            # an empty line is required after the headers
      signed_headers,                # signed headers
      payload_hash                   # payload hash (optional)
    ].join("\n")

    # Step 2: Create the String to Sign
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = "#{date_stamp}/#{config[:region]}/#{config[:service]}/#{AWS4_REQUEST_SCOPE}"
    string_to_sign = [
      algorithm,
      amz_date,
      credential_scope,
      buffer_to_hexstring(sha256(canonical_request))
    ].join("\n")

    # Step 3: Calculate the Signing Key
    signing_key = hmac_sha256_recursive("AWS4#{secret_key}", date_stamp, config[:region], config[:service], AWS4_REQUEST_SCOPE)

    # Step 4: Calculate the Signature
    signature = buffer_to_hexstring(hmac_sha256(signing_key, string_to_sign))

    # Step 5: Create Authorization Header
    authorization_header = "#{algorithm} Credential=#{access_key}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"

    # Step 6: Return the signed headers
    canonical_headers
      .transform_keys(&:downcase)
      .merge("Authorization" => authorization_header)
  end
end
