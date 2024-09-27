require "async"
require "base64"
require "json"
require "./app/services/backend/db"
require "./app/services/backend/fs"
require "./app/services/backend/s3"
require "./app/services/frontend/stateless"

# Make change to RSpec config to run tests in the order they are defined
RSpec.configure do |config|
  config.order = :defined
end

RSpec.describe StatelessFrontendSocket do
  db_config = DbBackendSocketConfig.new(
    "./tmp/frontend-test-storage/db.db",
    "test_storage",
    1.0,
  )
  fs_config = FsBackendSocketConfig.new(
    "./tmp/frontend-test-storage/fs/",
    "./tmp/frontend-test-storage/fs/_meta.json",
    1.0,
  )
  s3_config = S3BackendSocketConfig.new(
    "localhost:9000",
    "test-bucket",
    "minioadmin",
    "minioadmin",
    5.0,
  )

  # Sample test object json data
  new_object_ids = [
    "1temp/hello-world.txt",
    "1temp hello world.txt",
    "1temp_hello_world.txt",
    "2temp/hello-world.txt",
    "2temp hello world.txt",
    "2temp_hello_world.txt",
    "3temp/hello-world.txt",
    "3temp hello world.txt",
    "3temp_hello_world.txt"
  ]
  new_object_datas = [
    "File 1!!",
    "File 2\nTwo Lines!!",
    "File 3\nSecond Line\nThree Lines!!",
    "File 4!!",
    "File 5\nTwo Lines!!",
    "File 6\nSecond Line\nThree Lines!!",
    "File 7!!",
    "File 8\nTwo Lines!!",
    "File 9\nSecond Line\nThree Lines!!"
  ]
  new_object_payloads = [ *(0...(new_object_ids.length)) ].map { |i|
    payload = {
      "id" => new_object_ids[i],
      "data" => Base64.strict_encode64(new_object_datas[i])
    }
    payload
  }

  Sync do
    # Create an instances of `BackendSocket`s
    backend_sockets = [
      DbBackendSocket.new(db_config),
      FsBackendSocket.new(fs_config),
      S3BackendSocket.new(s3_config)
    ]
    # Close all backend sockets, to make sure that the frontend boots them on its own (by calling their init methods)
    backend_sockets.each { |socket|
      # socket.close().wait()
    }
    # Create an instance of StatelessFrontendSocket
    frontend = StatelessFrontendSocket.new(backend_sockets)

    describe "StatelessFrontendSocket.init" do
      it "initializes the frontend of the server, and resolves the is_ready promise" do
        Async do
          expect(frontend.is_ready.wait).to eq(true)
          backend_sockets.each { |socket|
            expect(socket.is_ready.status).to_not eq("pending")
          }
        end
      end
    end

    describe "StatelessFrontendSocket.write_object" do
      it "writes the data of three objects asynchronously" do
        Async do
          promises = new_object_payloads.map { |payload|
            frontend.write_object(payload).then(->(socket_index) { socket_index >= 0 })
          }
          expect(AsyncPromise.all(promises).wait).to eq(Array.new(promises.length, true))
        end
      end

      # TODO: this fails. investigate why.
      it "refuses to insert data for existing ids" do
        Async do
          promises = new_object_payloads.map { |payload|
            frontend.write_object(payload).then(->(socket_index) { socket_index >= 0 })
          }
          expect(AsyncPromise.all(promises).wait).to eq(Array.new(promises.length, false))
        end
      end
    end

    describe "StatelessFrontendSocket.read_object" do
      it "retrieves of all of the written objects along with their metadata" do
        Async do
          promises = new_object_payloads.map { |payload|
            frontend.read_object(payload["id"]).then(->(response) {
              response => {id:, size:, created_at:, data:}
              expect(size).to be_a(Numeric)
              expect(created_at).to be_a(Numeric)

              id == payload["id"] and data == payload["data"]
            })
          }
          expect(AsyncPromise.all(promises).wait).to eq(Array.new(promises.length, true))
        end
      end
    end

    # describe "FsBackendSocket.get_object" do
    #   it "retrieves the object data for the given id" do
    #     Async do
    #       data = socket.get_object(new_object_id).wait
    #       expect(data).to eq(new_object_data)
    #     end
    #   end
    # end

    # describe "FsBackendSocket.backup" do
    #   it "saves the metadata table to the filesystem as \"_meta.json\"" do
    #     Async do
    #       expect { socket.backup().wait }.to_not raise_error(StandardError)
    #     end
    #   end
    # end

    describe "StatelessFrontendSocket.close" do
      it "closes the frontend, and initiates the backup process of the backends, then closes them as well" do
        Async do
          expect { frontend.close().wait }.not_to raise_error(StandardError)
          expect { frontend.is_ready.wait }.to raise_error(/closed/)
          backend_sockets.each { |socket|
            expect { socket.is_ready.wait }.to raise_error(/closed/)
          }
        end
      end
    end

    describe "StatelessFrontendSocket.init" do
      it "reinitializes the frontend and the backend along with it, then creates a new resolved is_ready promise" do
        Async do
          frontend.init()
          expect(frontend.is_ready.wait).to eq(true)
          backend_sockets.each { |socket|
            expect(socket.is_ready.status).to_not eq("pending")
          }
        end
      end
    end

    describe "StatelessFrontendSocket.read_object" do
      it "retrieves our object from last time, when we backed up" do
        Async do
          promises = new_object_payloads.map { |payload|
            frontend.read_object(payload["id"]).then(->(response) {
              response => {id:, size:, created_at:, data:}
              expect(size).to be_a(Numeric)
              expect(created_at).to be_a(Numeric)

              id == payload["id"] and data == payload["data"]
            })
          }
          expect(AsyncPromise.all(promises).wait).to eq(Array.new(promises.length, true))
        end
      end
    end

    # TODO: implementing this will quicken testing
    # describe "StatelessFrontendSocket.del_object" do
    #   it "deletes the object associated with the id" do
    #     Async do
    #       expect(socket.del_object(new_object_id).wait).to eq(true)
    #     end
    #   end
    # end

    # describe "StatelessFrontendSocket.get_object_metadata after delete" do
    #   it "raises an error when trying to get metadata for a deleted object id" do
    #     Async do
    #       expect { socket.get_object_metadata(new_object_id).wait }.to raise_error(BackendNetworkError)
    #     end
    #   end
    # end

    describe "StatelessFrontendSocket.close" do
      it "closes the frontend, and initiates the backup process of the backends, then closes them as well" do
        Async do
          expect { frontend.close().wait }.not_to raise_error(StandardError)
          expect { frontend.is_ready.wait }.to raise_error(/closed/)
          backend_sockets.each { |socket|
            expect { socket.is_ready.wait }.to raise_error(/closed/)
          }
        end
      end
    end
  end
end
