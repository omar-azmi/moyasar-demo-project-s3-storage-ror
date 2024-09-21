
namespace :minio do
  desc "download the MinIO binary if it doesn't exist"
  task :download do
    minio_dir = "vendor/bin"
    minio_binary = "#{minio_dir}/minio"
    minio_url = "https://dl.min.io/server/minio/release/linux-amd64/minio"

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
end
