require "async"
require "json"
require "./app/services/backend/fs"

# Make change to RSpec config to run tests in the order they are defined
RSpec.configure do |config|
  config.order = :defined
end

RSpec.describe FsBackendSocket do
  working_config = FsBackendSocketConfig.new(
    "./storage/fs/",
    "./storage/fs/_meta.json",
    1.0,
  )

  # Define test object data
  new_object_id = "temp/hello-world.txt"
  new_object_data = "Hello World!!"

  # Create an instance of FsBackendSocket
  Sync do
    socket = FsBackendSocket.new(working_config)

    describe "FsBackendSocket.init" do
      it "initializes the backend and resolves the is_ready promise" do
        Async do
          expect(socket.is_ready.wait).to eq(true)
          expect(socket.is_online().wait).to be < 100 # latency should be under 100 ms
        end
      end
    end

    describe "FsBackendSocket.set_object" do
      it "inserts the data for a new id" do
        Async do
          socket.set_object(new_object_id, new_object_data).wait => { id:, size:, created_at: }
          expect(id).to eq(new_object_id)
          expect(size).to eq(new_object_data.length)
          expect(created_at).to be_a(Numeric)
        end
      end

      it "refuses to insert data for an existing id" do
        Async do
          expect { socket.set_object(new_object_id, new_object_data).wait }.to raise_error(BackendNetworkError)
        end
      end
    end

    describe "FsBackendSocket.get_object_metadata" do
      it "retrieves the metadata of an object from its id" do
        Async do
          socket.get_object_metadata(new_object_id).wait => { id:, size:, created_at: }
          expect(id).to eq(new_object_id)
          expect(size).to eq(new_object_data.length)
          expect(created_at).to be_a(Numeric)
        end
      end
    end

    describe "FsBackendSocket.get_object" do
      it "retrieves the object data for the given id" do
        Async do
          data = socket.get_object(new_object_id).wait
          expect(data).to eq(new_object_data)
        end
      end
    end

    describe "FsBackendSocket.backup" do
      it "saves the metadata table to the filesystem as \"_meta.json\"" do
        Async do
          expect { socket.backup().wait }.to_not raise_error(StandardError)
        end
      end
    end

    describe "FsBackendSocket.close" do
      it "closes the backend and rejects the is_ready promise" do
        Async do
          expect { socket.close().wait }.not_to raise_error(StandardError)
          expect { socket.is_ready.wait }.to raise_error("Filesystem backend closed.")
        end
      end
    end

    describe "FsBackendSocket.init" do
      it "reinitializes the backend fielsystem and creates a new resolved is_ready promise" do
        Async do
          socket.init()
          expect(socket.is_ready.wait).to eq(true)
          expect(socket.is_online().wait).to be < 100 # latency should be under 100 ms
        end
      end
    end

    describe "FsBackendSocket.get_object" do
      it "retrieves our object from last time, when we backed up" do
        Async do
          data = socket.get_object(new_object_id).wait
          expect(data).to eq(new_object_data)
        end
      end
    end

    describe "FsBackendSocket.del_object" do
      it "deletes the object associated with the id" do
        Async do
          expect(socket.del_object(new_object_id).wait).to eq(true)
        end
      end
    end

    describe "FsBackendSocket.get_object_metadata after delete" do
      it "raises an error when trying to get metadata for a deleted object id" do
        Async do
          expect { socket.get_object_metadata(new_object_id).wait }.to raise_error(BackendNetworkError)
        end
      end
    end

    describe "FsBackendSocket.backup" do
      it "saves the metadata table again to the filesystem as \"_meta.json\", and close the backend again" do
        Async do
          expect { socket.backup().wait }.to_not raise_error(StandardError)
          expect { socket.close().wait }.not_to raise_error(StandardError)
          expect { socket.is_ready.wait }.to raise_error("Filesystem backend closed.")
        end
      end
    end
  end
end
