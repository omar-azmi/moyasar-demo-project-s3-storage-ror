require "fileutils"
require "json"
require_relative "./base"


# FsBackendSocketConfig struct for filesystem config
# @param root [String] path of the filesystem local storage.
# @param meta_table [String] path of the metatable for local storage. it will resemble [MetaTable].
FsBackendSocketConfig = Struct.new(:root, :meta_table, :timeout)

# Default configuration for the filesystem backend
DEFAULT_FS_CONFIG = FsBackendSocketConfig.new(
  "./storage/fs/",
  "./storage/fs/_meta.json",
  5.0,
)

# MetaTable is a hash that maps IDs to MetaTableEntry
# MetaTableEntry stores metadata for objects in the storage
MetaTableEntry = Struct.new(:id, :size, :createdAt, :file)

# FsBackendSocket class for interacting with filesystem as a storage backend
class FsBackendSocket < StorageBackendSocket
  # attr_accessor :is_ready # inherited

  def initialize(config = {})
    super()
    config = config.is_a?(FsBackendSocketConfig) ? config.to_h : config
    # @type [S3BackendSocketConfig]
    @config = DEFAULT_FS_CONFIG.to_h.merge(config)
    # @type [Hash<StorageObjectId, MetaTableEntry>]
    @meta_table = {}
    # @type [Integer]
    @file_counter = nil
    self.is_ready = AsyncPromise.new()
    self.init()
  end

  # Initializes the filesystem backend by creating necessary directories and loading the meta table
  # @return [AsyncPromise<void>]
  def init
    self.is_ready = AsyncPromise.new()
    AsyncPromise.resolve().then(->(_) {
      begin
        self.ensure_dir(@config[:root])
        self.ensure_file(@config[:meta_table])
        meta_table_content = File.read(@config[:meta_table])
        @meta_table = JSON.parse(meta_table_content) rescue {}
        self.is_ready.resolve(true)
      rescue StandardError => reason
        self.is_ready.reject(BackendNetworkError.new("Failed to initialize filesystem storage location with reason: #{reason.message}"))
      end
    })
  end

  # Update/Backup the metadata of the files stored in this storage, in the "_meta.json" file.
  # @return [AsyncPromise<void>]
  def backup
    self.is_ready.then(->(_) {
      File.write(@config[:meta_table], JSON.pretty_generate(@meta_table))
    })
  end

  # Closes the backend by resetting `self.is_ready` and rejecting any new promises
  # @return [AsyncPromise<void>]
  def close
    self.is_ready = AsyncPromise.reject("Filesystem backend closed.")
    AsyncPromise.resolve()
  end

  # Checks if the backend is online by checking the root directory's existence.
  # Returns the time (in milliseconds) it takes to check.
  # @return [AsyncPromise<Float>]
  def is_online
    self.is_ready.then(->(backend_available) {
      unless backend_available == true
        raise BackendNetworkError.new("File system backend is connected, but is not available for requests")
      end
      delta_time = Time.now
      File.stat(@config[:root])
      delta_time = Time.now - delta_time
      delta_time * 1000 # latency in milliseconds
    }).catch(->(_) { nil })
  end

  # Retrieves object metadata by its ID.
  # @return [AsyncPromise<StorageObjectMetadata>]
  def get_object_metadata(id)
    self.is_ready.then(->(_) {
      metadata = @meta_table[id]
      if metadata.nil?
        raise BackendNetworkError.new("Metadata for id #{id} does not exist")
      end
      metadata.transform_keys(&:to_sym) => {file:, **meta}
      meta
    })
  end

  # Approves storing an object based on metadata, ensures the object does not already exist.
  # @return [AsyncPromise<boolean>]
  def approve_object_metadata(stats)
    stats => {id:, size:}
    self.is_ready.then(->(_) {
      if @meta_table[id]
        raise BackendNetworkError.new("The blob with id #{id} already exists.")
      end
      true
    })
  end

  # Retrieves an object (blob) by its ID.
  # @return [AsyncPromise<String>]
  def get_object(id)
    self.is_ready.then(->(_) {
      metadata = @meta_table[id]
      if metadata.nil?
        raise BackendNetworkError.new("Metadata for id #{id} does not exist.")
      end
      file_path = File.expand_path(metadata["file"], @config[:root])
      file_content = File.binread(file_path)
      file_content
    })
  end

  # Stores an object (blob) in the backend by its ID.
  # @param id [StorageObjectId] id of the object to store
  # @param data [String] the binary data (as a string) to store
  def set_object(id, data)
    self.is_ready.then(->(_) {
      if @meta_table[id]
        raise BackendNetworkError.new("The blob with id #{id} already exists.")
      end
      file_name = self.increment_file_counter().wait.to_s # get the numeric name of the file to store in the filesystem
      file_path = File.expand_path(file_name, @config[:root])
      File.binwrite(file_path, data) # writing binary data to the file
      metadata = {
        id: id,
        size: data.bytesize,
        created_at: (Time.now.to_f * 1000).to_i,
        file: file_name
      }
      @meta_table[id] = metadata.transform_keys(&:to_s)
      metadata => {file:, **meta}
      meta
    })
  end

  # Deletes an object by its ID
  # for internal testing purposes only
  # @return [AsyncPromise<Boolean>]
  def del_object(id)
    self.is_ready.then(->(_) {
      metadata = @meta_table[id]
      if metadata.nil?
        raise BackendNetworkError.new("Metadata for id #{id} does not exist.")
      end
      file_path = File.expand_path(metadata["file"], @config[:root])
      File.delete(file_path) if File.exist?(file_path)
      @meta_table.delete(id)
      true
    }).catch(->(reason) {
      raise BackendNetworkError.new("Failed to delete object #{id}: #{reason}")
    })
  end

  # Increment the file counter
  private def increment_file_counter
    get_file_counter.then(->(counter) { @file_counter += 1 })
  end

  # Get the current file counter, initializing it if necessary
  private def get_file_counter
    self.is_ready.then(->(_) {
      # first initiate the file_counter if it not already known.
      # for this, we will read the meta_table and find the largest numeric file name (inside the fs) that is stored.
      if @file_counter.nil?
        max_file_number = @meta_table.map { |id, meta| meta["file"].to_i }.max || 0
        @file_counter = max_file_number
      end
      @file_counter
    })
  end

  # Ensure directory existence, else create it
  private def ensure_dir(path)
    FileUtils.mkdir_p(path) unless File.directory?(path)
  end

  # Ensure file existence, else create it (along with any intermediate folders required)
  private def ensure_file(path)
    unless File.exist?(path)
      self.ensure_dir(File.dirname(path))
      FileUtils.touch(path)
    end
  end
end
