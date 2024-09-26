require "async"
require "sqlite3"
require "./app/services/backend/db"

# Make sure tests run in order
RSpec.configure do |config|
  config.order = :defined
end

RSpec.describe DbBackendSocket do
  working_config = DbBackendSocketConfig.new(
    "./storage/db/test.db",
    "test_storage",
    1.0,
  )

  Sync do
    socket = DbBackendSocket.new(working_config)
    new_object_id = "temp/hello-world.txt"
    new_object_data = "Hello World!! (SQLite)"

    describe "DbBackendSocket.init" do
      it "should initialize the sqlite database and resolve is_ready" do
        Async do
          expect(socket.is_ready.wait).to eq(true)
          expect(socket.is_online().wait).to be < 100 # latency should be under 100 ms
        end
      end
    end

    describe "DbBackendSocket.set_object" do
      it "should insert the data for a new id" do
        Async do
          socket.set_object(new_object_id, new_object_data).wait => {id:, size:, created_at:}
          expect(id).to eq(new_object_id)
          expect(size).to eq(new_object_data.length)
          expect(created_at).to be_a(Numeric)
        end
      end

      it "should refuse to insert data for an existing id" do
        Async do
          expect { socket.set_object(new_object_id, new_object_data).wait }.to raise_error(BackendNetworkError, /already exists/)
        end
      end
    end

    describe "DbBackendSocket.get_object_metadata" do
      it "should get the metadata of an object from id" do
        Async do
          socket.get_object_metadata(new_object_id).wait => {id:, size:, created_at:}
          expect(id).to eq(new_object_id)
          expect(size).to eq(new_object_data.length)
          expect(created_at).to be_a(Numeric)
        end
      end
    end

    describe "DbBackendSocket.get_object" do
      it "should retrieve the binary data stored for a given id" do
        Async do
          object_data = socket.get_object(new_object_id).wait
          expect(object_data).to eq(new_object_data)
        end
      end
    end

    describe "DbBackendSocket.del_object" do
      it "should delete the object associated with the id" do
        Async do
          expect(socket.del_object(new_object_id).wait).to eq(true)
        end
      end
    end

    describe "DbBackendSocket.get_object_metadata after delete" do
      it "should raise an error when getting metadata for a deleted object id" do
        Async do
          expect { socket.get_object_metadata(new_object_id).wait }.to raise_error(BackendNetworkError, /does not exist/)
        end
      end
    end

    describe "DbBackendSocket.close" do
      it "closes database and rejects further is_ready calls" do
        Async do
          expect(socket.close().wait).to eq(nil)
          expect { socket.is_ready().wait }.to raise_error(BackendNetworkError, /closed/)
        end
      end
    end
  end
end
