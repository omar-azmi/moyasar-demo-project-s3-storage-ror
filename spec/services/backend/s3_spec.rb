require "async"
require "rake"
require "./app/services/backend/base"
require "./app/services/backend/s3"


puts "[WARNING] minio server must NOT be running when this test is executed"

RSpec.describe is_minio_bucket_available do
  working_config = S3BackendSocketConfig.new(
    "localhost:9000",
    "s3-bucket",
    "minioadmin",
    "minioadmin",
    5.0,
  )

  # Close any running instance of the minio server via our rake task "minio:close".
  rake = Rake::Application.new()
  Rake.application = rake
  rake.init()
  rake.load_rakefile()
  rake["minio:close"].execute() # we call `execute` instead of `invoke` because the same task cannot be run again it is `invoke`d (but `execute` does allow for that)
  sleep(1)

  Sync do
    describe "#is_minio_bucket_available" do
      it "raises an error when minio server (the host) is not running" do
        expect { is_minio_bucket_available(working_config).wait() }.to raise_error(BackendNetworkError)
      end
    end

    describe "#is_minio_bucket_available" do
      it "raises an error when tcp communication timeout due to non-existing minio server host" do
        # an example of a very-likely fake host that will timeout is "192.168.0.254".
        # but this address is not very reliable depending on your LAN config (for example, a company may use 172.10.x.x for LAN, resulting in "192.168.0.254" being immediately rejected as an incorrect host).
        # thus, I have noticed a more reliable fake host is the use of any number (except for "0" which transforms to "0.0.0.0" aka "localhost"), without any dot separators or a top-level domain name (TLD) such as ".com" or ".org".
        # UPDATE: unfortunately, using pure numeric host only timeouts in curl, but not in ruby's standard net library.
        # thus I am using "0.0.1.0" instead, since it is supposed to be in the NAT range of your localhost machine, but at the same time it will probably not exist, and thus timeout (works in both ruby and curl).
        fake_host = "0.0.1.0"
        nonexisting_host_config = working_config.to_h.merge({ host: fake_host, timeout: 1.0 })
        expect { is_minio_bucket_available(nonexisting_host_config).wait() }.to raise_error(BackendNetworkError)
      end
    end


    describe "#is_minio_bucket_available" do
      it "returns `false` when minio host is available but non-existing bucket is being accessed, or when wrong credentials are given.\n" \
        "and returns `true` when correct credentials and bucket information is provided" do
        # Now, initiate minio via our rake task "minio:start", so that we can perform further tests.
        rake["minio:start"].execute()
        sleep(3)

        # test for wrong bucket info
        fake_bucket_config = working_config.to_h.merge({ bucket: "fake_bucket" })
        expect(is_minio_bucket_available(fake_bucket_config).wait()).to eq(false)

        # test for wrong credentials
        fake_credentials_config = working_config.to_h.merge({ access_key: "fake_access_key", secret_key: "fake_secret_key" })
        expect(is_minio_bucket_available(fake_credentials_config).wait()).to eq(false)

        # test for correct credentials and bucket info
        expect(is_minio_bucket_available(working_config).wait()).to eq(true)

        # Close the minio server via our rake task "minio:close", since our tests are now complete.
        rake["minio:close"].execute()
      end
    end
  end
end
