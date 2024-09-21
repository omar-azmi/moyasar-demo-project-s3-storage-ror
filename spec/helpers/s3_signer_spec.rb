require "./lib/helpers/s3_signer"

RSpec.describe S3Signer do
  include S3Signer

  # In the tests that follow, we recreate the example provided in amazon's guide for Amazon Signature V4:
  # "https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html"

  sample_access_key = "AKIAIOSFODNN7EXAMPLE"
  sample_secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  sample_host = "examplebucket.s3.amazonaws.com"
  sample_pathname = "/test.txt"
  sample_amz_time = "20130524T000000Z"

  # effective canonical test header used in amazon's example (but it has been un-normalized for testing)
  sample_headers = {
    "host" => sample_host,
    "X-AMZ-DATE" => sample_amz_time,
    "raNGe" => "bytes=0-9",
    "x-amz-content-sha256" => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }

  describe "#http_headers_to_string" do
    it "returns a normalized string version of http headers, so that they are sorted (by key name)," \
      "lowered in key name casing, and have the values trimmed off of their whitespaces" do
      expected_normalized_header_string =
      "host:#{sample_host}\n" \
      "range:bytes=0-9\n" \
      "x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n" \
      "x-amz-date:#{sample_amz_time}"

      expect(http_headers_to_string(sample_headers)).to eq(expected_normalized_header_string)
    end
  end

  describe "#get_http_header_keys" do
    it "returns the sorted list of header keys from a header hash object" do
      expected_sorted_headers = [ "host", "range", "x-amz-content-sha256", "x-amz-date" ]
      expect(get_http_header_keys(sample_headers)).to match_array(expected_sorted_headers)
    end
  end

  describe "#get_signed_headers" do
    it "generates the correct AWS Signature Version 4, and adds it to the headers' \"Authorization\" key" do
      # the original headers here are short because we expect the signing function to add all of the necessary headers on its own.
      original_headers = {
        "raNGe" => "bytes=0-9"
      }
      signed_headers = get_signed_headers(sample_host, sample_pathname, sample_access_key, sample_secret_key, {
        method: "gET",
        payload: "",
        headers: original_headers,
        date: "20130524T000000Z"
      })
      authfield = signed_headers["Authorization"]
      expect(authfield).to start_with("AWS4-HMAC-SHA256")
      expect(authfield).to include("Credential=#{sample_access_key}")
      expect(authfield).to include("SignedHeaders=host;range;x-amz-content-sha256;x-amz-date")
      expect(authfield).to end_with("Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")

      original_canonical_headers_with_auth = sample_headers.merge({ "Authorization" =>signed_headers["Authorization"] })
      expect(http_headers_to_string(signed_headers)).to eq(http_headers_to_string(original_canonical_headers_with_auth))
    end
  end
end
