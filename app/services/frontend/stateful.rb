require "base64"
require "fileutils"
require "sqlite3"
require_relative "./base"
require_relative "./stateless"

# StatefulFrontendSocketConfig struct for frontend socket config
# @param path [String] path of where the object-info-record database file exists in the filesystem.
# @param name [String] the name of the storage table within the database.
# @param aliases [Array<String>] the alias name given to each backend storage, in  the same order in which they will be passed on to the constructor of `StatefulFrontendSocket`.
StatefulFrontendSocketConfig = Struct.new(:path, :name, :aliases)

# Default configuration for the filesystem backend
DEFAULT__FRONTEND_DB_CONFIG = StatefulFrontendSocketConfig.new(
  "./storage/frontend/records.db",
  "objects",
  [ "db_1", "fs_1", "s3_1" ],
)

# `StatefulFrontendSocketObjectEntry` is the struct that will be used for recording each unique object (by id) in the `StatefulFrontendSocket`'s database
# @param id [String] the id of the object stored in one of the backends.
# @param backend [String] the alias name of the backend it was stored in (must be one of [StatefulFrontendSocketConfig.aliases] of the current running frontend socket).
# @param bearer [nil, String] the bearer/owner of the object. `nil` and empty strings will be treated as no owner (i.e. public access).
#        Any read request made with a bearer for an id that is publicly available will be resolved with a 200.
#        However, any read request made with a bearer for an id that has a different bearer, will be rejected with a 401 (unauthorized).
StatefulFrontendSocketObjectEntry = Struct.new(:id, :backend, :bearer)

# When a wrong bearer tries to read a piece of data, this error is raised
class WrongCredentialsError < FrontendNetworkError
end

# This frontend of the simple storage server stores user payload data in randomly picked backend storage.
# In addition, it keeps records of where it stored each payload in an ActiveRecord database, which is a part of Rails standard distribution.
# Since it keeps a record, we call this frontend "stateful", as it has a memory of its own, and it must be backed up and restored for it to function after a reboot/init
# Moreover, this frontend also accepts an optional "bearer" field in the user's json-like payload, which should specify who owns that piece of object.
# When the bearer is specified during object writing, the bearer field must also be specified when reading the object again, otherwise a nil would be returned (and the server router should respond back with an http 401 (Unauthorized))
class StatefulFrontendSocket < StatelessFrontendSocket
  # Initialize the frontend storage, managing multiple backend storage sockets.
  # @param backend_sockets [Array<StorageBackendSocket>] The backend storage sockets to manage.
  # @param config [StatefulFrontendSocketConfig] The configuration of the frontend.
  def initialize(backend_sockets, config = {})
    super(backend_sockets)
    # @sockets = backend_sockets # inherited
    # @type [nil, SQLite3::Database]
    @db = nil
    config = config.is_a?(StatefulFrontendSocketConfig) ? config.to_h : config
    @config = DEFAULT__FRONTEND_DB_CONFIG.to_h.merge(config)
    if @config[:aliases].length != @sockets.length
      raise FrontendNetworkError.new("The number of backend sockets provided and the number of aliases/names give to assign to them are not equal.")
    end
    self.init()
  end

  # Initialize all backend storage sockets and ensure they are ready. In addition to also initializing its own database.
  # @return [AsyncPromise<void>]
  def init
    @config => {path:, name:}
    AsyncPromise.resolve()
      # First we initialize the frontend's record keeping database
      .then(->(_) {
        begin
          self.ensure_file(path)
          @db = SQLite3::Database.new(path)
          @db.execute <<-SQL
            CREATE TABLE IF NOT EXISTS #{name} (
              id TEXT PRIMARY KEY, -- the id of the stored object (also the primary key)
              backend TEXT,        -- the alias of the backend it is stored in
              bearer TEXT          -- the owner of the data. use an empty string "" for public data
            );
          SQL
        rescue StandardError => reason
          raise FrontendNetworkError.new("Failed to initialize sqlite3 database storage with reason: #{reason.message}")
        end
      })
      # Next, we initialize all backend storages by calling the super class's init method (which also resolves the is_ready state)
      .then(->(_) {
        super()
      })
      .catch(->(reason) {
        self.is_ready.reject(reason)
      })
  end

  # Trigger a backup process across all backend sockets, and the frontend's record table.
  # @return [AsyncPromise<void>]
  def backup
    # No operation needed of self record backup, since the sqlite3 library automatically saves all changes back to the database file.
    # for the backend backup, we simply call the super method
    super()
  end

  # Close the frontend database table, and all of the backend storage sockets.
  # @return [AsyncPromise<void>]
  def close
    unless @db.nil?
      self.is_ready = AsyncPromise.reject(FrontendNetworkError.new("Frontend has been closed."))
      @db.close()
    end
    # the super method closes all backends
    super()
  end

  # Read an object from the storage, given the `id` of the object, and an optional `bearer` name (owner), if the object is not for public viewing.
  # @param id [String] The ID of the object to read.
  # @param bearer [nil, String] The Bearer of that object. use `nil` or an empty string for public data reading.
  # @return [AsyncPromise<[nil, StorageObjectReadJson]>]
  def read_object(id, bearer: nil)
    bearer = bearer || ""
    @config => {name:, aliases:}
    self.is_ready.then(->(_) {
      # @type [Array<Array<Any>>]
      records = @db.execute("SELECT backend, bearer FROM #{name} WHERE id = ?", [ id ])
      if records.empty?
        puts FrontendNetworkError.new("Record for id \"#{id}\" does not exist")
        return nil
      end
      backend, actual_bearer = records[0]
      if bearer != actual_bearer
        raise WrongCredentialsError.new("Current bearer does not have permission to read object of id: #{id}")
      end
      backend_index = aliases.find_index(backend)
      # redundancy commented below
      # if backend_index.nil?
      #   puts FrontendNetworkError.new("The backend socket with the alias (name) \"#{backend}\" is not attached to this frontend")
      #   return nil
      # end
      # socket = @sockets[backend_index]
      # if socket.is_online().wait().nil?
      #   puts FrontendNetworkError.new("The backend socket with the alias (name) \"#{backend}\" is not currently online (but is attached).")
      #   return nil
      # end
      super(id, sockets: [ backend_index ])
    })
  end

  # Write an object to a randomly picked backend socket (which must be online).
  # @param payload [StorageObjectWriteJson] The payload of the object data that needs to be stored.
  # @param bearer [nil, String] The Bearer of that object. use `nil` or an empty string for public data reading.
  # @return [AsyncPromise<Integer>] the return value reflects which backend socket took in our data. it will be `-1` if the writing was unsuccessful.
  def write_object(payload, bearer: nil)
    bearer = bearer || ""
    # @type [String]
    id = payload["id"]
    # @type [nil, String] the data in binary format, not as a base64 string. we only decode after we are certain that a backend is willing to accept the data
    data_blob = nil
    @config => {name:, aliases:}
    self.is_ready.then(->(_) {
      # first, we ensure that the `id` has not already been used (i.e. not in our record)
      # @type [Array<Array<Any>>]
      unless @db.execute("SELECT id FROM #{name} WHERE id = ?", [ id ]).empty?
        puts FrontendNetworkError.new("The record with id #{id} already exists.")
        return -1
      end
      # next, we randomly pick a backend to store our payload, ask it if it is online, then ask it to for approval of the payload.
      # if the process does not succeed, we move to the next backend.
      # DONE: the whole process can be carried out by the super method, but then we won't know which backend actually stored the data, and so we wont be able to record it.
      #       later on, make it so that the super method returns the index of the backend in which the data was stored
      super(payload)
    }).then(->(backend_index) {
      # if -1 was given as the backend socket index, then it means that the data was not stored, thus we will return a -1 early, since no change need to be made to the record database
      return backend_index if backend_index < 0
      backend_alias = aliases[backend_index]
      # inserting the data record into the database table
      @db.execute("INSERT INTO #{name} (id, backend, bearer) VALUES (?, ?, ?)", [ id, backend_alias, bearer ])
      backend_index
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
