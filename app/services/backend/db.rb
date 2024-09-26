require "fileutils"
require "sqlite3"
require_relative "./base"

# DbBackendSocketConfig struct for sqlite database config
# @param path [String] path of where the database file exists in the filesystem.
# @param name [String] the name of the storage table within the database.
# @param timeout [Float] TODO: how long to wait before timing out of a database request.
DbBackendSocketConfig = Struct.new(:path, :name, :timeout)

# Default configuration for the filesystem backend
DEFAULT_DB_CONFIG = DbBackendSocketConfig.new(
  "./storage/db/main.db",
  "storage",
  5.0,
)

# DbBackendSocket class for interacting with database as a storage backend
class DbBackendSocket < StorageBackendSocket
  # attr_accessor :is_ready # inherited

  def initialize(config = {})
    super()
    config = config.is_a?(DbBackendSocketConfig) ? config.to_h : config
    # @type [S3BackendSocketConfig]
    @config = DEFAULT_DB_CONFIG.to_h.merge(config)
    # @type [nil, SQLite3::Database]
    @db = nil
    # IMPORTANT: the arrays returned by `@db.execute` are frozen. thus I cannot mutate them via push, pop, shift, etc...
    self.is_ready = AsyncPromise.new()
    self.init()
  end

  # Initializes the database backend by invoking sqlite
  # @return [AsyncPromise<void>]
  def init
    @config => {path:, name:}
    self.is_ready = AsyncPromise.new()
    AsyncPromise.resolve().then(->(_) {
      begin
        self.ensure_file(path)
        @db = SQLite3::Database.new(path)
        @db.execute <<-SQL
          CREATE TABLE IF NOT EXISTS #{name} (
            id TEXT PRIMARY KEY, -- the id of the stored object (also the primary key)
            size INTEGER,        -- byte size of the binary data held
            created_at INTEGER,  -- time of creation of the object as milliseconds since epoch
            data BLOB            -- the binary data itself
          );
        SQL
        self.is_ready.resolve(true)
      rescue StandardError => reason
        self.is_ready.reject(BackendNetworkError.new("Failed to initialize sqlite3 database storage with reason: #{reason.message}"))
      end
    })
  end

  # No operation needed since the sqlite3 library automatically saves all changes back to the database file.
  # @return [AsyncPromise<void>]
  def backup
    AsyncPromise.resolve()
  end

  # Closes the backend database, and renews `self.is_ready` to a new pre-rejected promise
  # TODO: scheck how to close db
  # @return [AsyncPromise<void>]
  def close
    unless @db.nil?
      self.is_ready = AsyncPromise.reject(BackendNetworkError.new("Database backend closed."))
      @db.close()
    end
    AsyncPromise.resolve()
  end

  # Checks if the database backend is available by doing a quick SELECT operation on it.
  # Returns the time (in milliseconds) it takes to check.
  # @return [AsyncPromise<Float>]
  def is_online
    self.is_ready.then(->(backend_available) {
      unless backend_available == true
        raise BackendNetworkError.new("Database backend is connected, but is not available for requests")
      end
      delta_time = Time.now
      @db.execute("SELECT 1")
      delta_time = Time.now - delta_time
      delta_time * 1000 # latency in milliseconds
    }).catch(->(_) { nil })
  end

  # Retrieves object metadata by its ID.
  # @return [AsyncPromise<StorageObjectMetadata>]
  def get_object_metadata(id)
    @config => {name:}
    self.is_ready.then(->(_) {
      # @type Array<Array<Any>>
      records = @db.execute("SELECT id, size, created_at FROM #{name} WHERE id = ?", [ id ])
      if records.empty?
        raise BackendNetworkError.new("Metadata for id #{id} does not exist")
      end
      meta = records[0]
      { id: meta[0], size: meta[1], created_at: meta[2] }
    })
  end

  # Approves storing an object based on metadata, ensures the object does not already exist.
  # @return [AsyncPromise<boolean>]
  def approve_object_metadata(stats)
    @config => {name:}
    stats => {id:, size:}
    self.is_ready.then(->(_) {
      unless @db.execute("SELECT id FROM #{name} WHERE id = ?", [ id ]).empty?
        raise BackendNetworkError.new("The record with id #{id} already exists.")
      end
      true
    })
  end

  # Retrieves an object (blob) by its ID.
  # @return [AsyncPromise<String>]
  def get_object(id)
    @config => {name:}
    self.is_ready.then(->(_) {
      if @db.execute("SELECT id FROM #{name} WHERE id = ?", [ id ]).empty?
        raise BackendNetworkError.new("Metadata for id #{id} does not exist.")
      end
      matching_records = @db.execute("SELECT data FROM #{name} WHERE id = ?", [ id ])
      content = matching_records[0][0]
      content
    })
  end

  # Stores an object (blob) in the backend by its ID.
  # @param id [StorageObjectId] id of the object to store
  # @param data [String] the binary data (as a string) to store
  def set_object(id, data)
    @config => {name:}
    self.is_ready.then(->(_) {
      unless @db.execute("SELECT id FROM #{name} WHERE id = ?", [ id ]).empty?
        raise BackendNetworkError.new("The record with id #{id} already exists.")
      end
      size = data.bytesize
      created_at = (Time.now.to_f * 1000).to_i
      data_blob = SQLite3::Blob.new(data) # wrap the binary data as an SQL compatible BLOB
      # inserting the data record into the database table
      @db.execute("INSERT INTO #{name} (id, size, created_at, data) VALUES (?, ?, ?, ?)", [ id, size, created_at, data_blob ])
      { id: id, size: size, created_at: created_at }
    })
  end

  # Deletes an object by its ID
  # for internal testing purposes only
  # @return [AsyncPromise<Boolean>]
  def del_object(id)
    @config => {name:}
    self.is_ready.then(->(_) {
      if @db.execute("SELECT id FROM #{name} WHERE id = ?", [ id ]).empty?
        raise BackendNetworkError.new("Metadata for id #{id} does not exist.")
      end
      @db.execute("DELETE FROM #{name} WHERE id = ?", [ id ])
      true
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
