require "./lib/helpers/crypto"

RSpec.describe CryptoHelper, type: :helper do
  include CryptoHelper

  describe "#binary_to_hexstring" do
    it "returns the correct hex-string representation of a binary string" do
      message = "\x00hello world\x01\x02\x03\xff"
      expected_hex_string = "0068656c6c6f20776f726c64010203ff"
      expect(
        binary_to_hexstring(message)
      ).to eq(expected_hex_string)
    end
  end

  describe "#sha256" do
    it "returns the correct SHA256 hash of a message" do
      message = "hello world"
      expected_hash = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
      expect(binary_to_hexstring(
        sha256(message)
      )).to eq(expected_hash)
    end
  end

  describe "#hmac_sha256" do
    it "returns the correct HMAC-SHA256 signature for a key and message" do
      key = "secret 1"
      message = "hello world"
      expected_hmac = "0335641ddad0022d6fc1fbeaa3d322a7ae8b651b6455e582bc50af2b9e890dc8"
      expect(binary_to_hexstring(
        hmac_sha256(key, message)
      )).to eq(expected_hmac)
    end
  end

  describe "#hmac_sha256_recursive" do
    it "returns the correct HMAC-SHA256 for multiple messages recursively" do
      messages = [ "secret 1", "hello world", "secret 2" ]
      expected_recursive_hash = "c74fb55d0d78a3e0c524404012d3139b04e2d534cee19525a0228ebc80a769b3"
      expect(binary_to_hexstring(
        hmac_sha256_recursive(*messages)
      )).to eq(expected_recursive_hash)
    end

    it "raises an error if fewer than two messages are provided" do
      expect { hmac_sha256_recursive("only one message") }.to raise_error(ArgumentError)
    end
  end
end
