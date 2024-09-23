
namespace :minio do
  # the location to download minio from
  minio_url = "https://dl.min.io/server/minio/release/linux-amd64/minio"
  # the directory in which the minio binary will be placed
  minio_dir = "vendor/bin/"
  # the path of the minio binary
  minio_binary = "#{minio_dir}minio"
  # the storage directory in which minio's buckets will be stored
  minio_storage = "storage/minio/"

  desc "download the MinIO binary if it doesn't exist."
  task :download do
    # Ensure the vendor/bin directory exists
    unless File.directory?(minio_dir)
      FileUtils.mkdir_p(minio_dir)
      puts "creating directory for binary at: \"#{minio_dir}\""
    end

    # Download MinIO binary if it doesn't already exist
    unless File.exist?(minio_binary)
      puts "downloading MinIO..."
      require "open-uri"

      URI.open(minio_url) do |download|
        File.open(minio_binary, "wb") do |file|
          file.write(download.read)
        end
      end

      puts "MinIO downloaded to: \"#{minio_binary}\""
    else
      puts "MinIO already exists at: \"#{minio_binary}\""
    end

    # Make the binary executable
    File.chmod(0755, minio_binary)
    puts "the binary was given execution permissions."
  end

  desc "run the MinIO binary with default setup, if it isn't already running."
  task :start do
    # Check if minio is running via "pgrep" shell command, which finds it PID
    pid = `pgrep minio`.to_i
    if pid > 0
      puts "MinIO is already running at PID: #{pid}"
    else
      pid = spawn("#{minio_binary} server \"#{minio_storage}\" --console-address :9001", [ :out, :err ] => "/dev/null")
      # Detach the process so it doesn't block the Ruby script
      Process.detach(pid)
      puts "MinIO started with PID: #{pid}"
    end
  end

  desc "kill (interrupt) any running instances of the MinIO binary."
  task :close do
    # get the PID of any running MinIO instances via the "pgrep" shell command
    pid = `pgrep minio`.to_i
    if pid > 0
      # send an interrupt signal ("SIGINT" aka ctrl+c) to the running minio process, so that it shuts down
      Process.kill("INT", pid)
      puts "MinIO (PID: #{pid}) was closed"
    else
      puts "MinIO is not running"
    end
  end
end
