require "json"
require "./app/services/backend/db"
require "./app/services/backend/fs"
require "./app/services/backend/s3"
require "./app/services/frontend/stateful"
require "./lib/helpers/async_promise"


db_config = DbBackendSocketConfig.new(
  "./storage/frontend-storage/db.db",
  "test_storage",
  1.0,
)
fs_config = FsBackendSocketConfig.new(
  "./storage/frontend-storage/fs/",
  "./storage/frontend-storage/fs/_meta.json",
  1.0,
)
s3_config = S3BackendSocketConfig.new(
  "localhost:9000",
  "front-bucket",
  "minioadmin",
  "minioadmin",
  5.0,
)
front_config = StatefulFrontendSocketConfig.new(
  "./storage/frontend-storage/records.db",
  "objects",
  [ "db_1", "fs_1", "s3_1" ],
)

# This becomes a global variable, available to our controller (without the need for importation/require)
STORAGE_FRONTEND_SOCKET = StatefulFrontendSocket.new([
  DbBackendSocket.new(db_config),
  FsBackendSocket.new(fs_config),
  S3BackendSocket.new(s3_config)
], front_config)


# This background thread will do for periodic backups every minute
# TODO: hogging on a new thread may reduce performance
Thread.new do
  Async do
    loop do
      sleep(60)
      begin
        puts "Performing periodic backup..."
        STORAGE_FRONTEND_SOCKET.backup().wait()
      rescue => error
        puts "Error during backup: #{error.message}"
      end
    end
  end
end


# Handling server shutdown to call the `close` method
Signal.trap("INT") do
  puts "Shutting down... calling the `close` method on STORAGE_FRONTEND_SOCKET"
  begin
    STORAGE_FRONTEND_SOCKET.backup().wait()
    STORAGE_FRONTEND_SOCKET.close().wait()
  rescue => error
    puts "Error during shutdown: #{error.message}"
  else
    puts "Successfully backed up storage server and closed it."
  end
end
