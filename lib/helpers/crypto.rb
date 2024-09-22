
require "openssl"

module CryptoHelper
  extend self

  # SHA-256 hash function
  # @param message [String] The message or binary to hash
  # @return [String] The SHA256 binary hash (as a binary string buffer)
  public def sha256(message)
    digest = OpenSSL::Digest::SHA256.new
    digest.digest(message)
    # to convert the binary string to a hexadecimal representation, use the `unpack1("H*")` method of the binary string
  end

  # HMAC-SHA256 function
  # @param key [String] The key to use for the HMAC signing
  # @param message [String] The message to sign
  # @return [String] The HMAC binary hash (as a binary string buffer)
  public def hmac_sha256(key, message)
    digest = OpenSSL::Digest::SHA256.new
    hmac = OpenSSL::HMAC.digest(digest, key, message)
    # to convert the binary string to a hexadecimal representation, use the `unpack1("H*")` method of the binary string
  end

  # Apply HMAC-SHA256 recursively on multiple messages/binaries
  # @param messages [Array<String>] The list of messages to hash recursively. There should be at least 2 items.
  # @return [String] The final HMAC binary hash (as a binary string buffer)
  public def hmac_sha256_recursive(*messages)
    raise ArgumentError, "At least two messages are required" if messages.length < 2

    hash = hmac_sha256(messages.shift, messages.shift)
    until messages.empty?
      hash = hmac_sha256(hash, messages.shift)
    end
    hash
  end

  # Transform a binary string to a hex-string representation
  # @param buffer [String] The binary string to get a hex representation of
  # @return [String] The hex representation of the input binary string buffer
  public def buffer_to_hexstring(buffer)
    buffer.unpack1("H*")
  end
end
