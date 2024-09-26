require "async"
require "net/http"
require "./app/services/backend/s3"


# Make change to rspec config to run tests in the order they are defined (not in parallel or out of order, as they are by default)
RSpec.configure do |config|
  config.order = :defined
end

RSpec.describe S3BackendSocket do
  working_config = S3BackendSocketConfig.new(
    "localhost:9000",
    "s3-bucket",
    "minioadmin",
    "minioadmin",
    5.0,
  )

  # # Make sure that the minio server is not running before the test (it should be booted automatically).
  # before(:context) do
  #   MinIO.shutdown().wait()
  # end
  # # Close the minio server via our rake task "minio:close", after our tests are complete.
  # after(:context) do
  #   MinIO.shutdown().wait()
  # end

  Sync do
    # Close any running instance of the minio server via our rake task "minio:close".
    MinIO.shutdown().wait()
    # @type [S3BackendSocket]
    socket = S3BackendSocket.new(working_config)
    new_object_id = "temp/hello-world.txt"
    new_object_data = "Hello World!!"

    describe "S3BackendSocket.init" do
      it "when socket.is_ready is resolved, then minio sever must be running" do
        Async do
          expect(socket.is_ready.wait).to eq(true)
          expect(socket.is_online().wait).to be < 100 # latency should be under 100 ms
        end
      end
    end

    describe "S3BackendSocket.set_object" do
      it "should insert the data for a new id" do
        Async do
          socket.set_object(new_object_id, new_object_data).wait => {id:, size:, created_at:}
          expect(id).to eq(new_object_id)
          expect(size).to eq(new_object_data.bytesize)
          expect(created_at).to be_a(Numeric)
        end
      end

      it "should refuse to insert data for an existing id" do
        # TODO: should I implement this on the socket level?
        # Async do
        #   expect { socket.set_object(new_object_id, new_object_data).wait }.to raise_error()
        # end
      end
    end

    describe "S3BackendSocket.get_object_metadata" do
      it "should get the metadata of an object from id" do
        Async do
          socket.get_object_metadata(new_object_id).wait => {id:, size:, created_at:}
          expect(id).to eq(new_object_id)
          expect(size).to eq(new_object_data.bytesize)
          expect(created_at).to be_a(Numeric)
        end
      end
    end

    describe "S3BackendSocket.get_object" do
      it "should retrieve the object's data back from server" do
        Async do
          expect(socket.get_object(new_object_id).wait).to eq(new_object_data)
        end
      end
    end

    describe "S3BackendSocket.del_object" do
      it "should delete the object associated with the id" do
        Async do
          expect(socket.del_object(new_object_id).wait).to eq(true)
        end
      end
    end

    describe "S3BackendSocket.get_object_metadata after delete" do
      it "should raise an error when getting the metadate of a deleted object id" do
        Async do
          expect { socket.get_object_metadata(new_object_id).wait }.to raise_error("Failed to retrieve metadata for object #{new_object_id}")
        end
      end
    end

    describe "S3BackendSocket.close" do
      it "closes minio server and flicks socket.is_ready an new rejected promise" do
        Async do
          expect { socket.close().wait }.to_not raise_error()
          expect { socket.is_ready().wait }.to raise_error("MinIO server has been shut down.")
        end
      end
    end
  end
end
