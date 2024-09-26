require "./lib/helpers/async_promise"
require_relative "../backend/base"

# Frontend sockets must use this custom exception for frontend network originated errors
class FrontendNetworkError < StandardError
end

### StorageFrontendSocket abstract base class.
# @abstract Subclasses must implement all abstract methods.
class StorageFrontendSocket
  # This promise is resolved to a [true] value when the frontend storage server is ready to take requests (all backends have their `is_ready` resolved or timedout).
  # @return [AsyncPromise<Boolean>]
  attr_accessor :is_ready

  # Implementation must also contain the @sockets private variable that will hold an array of backend storage sockets [Array<StorageBackendSocket>]
  # @sockets

  # Read an object blob from the simple storage server.
  # The actual http server-router of this simple storage should hook this method to resolve the `GET` http request at the path `/v1/blobs/<id>`.
  # @param id [StorageObjectId] The ID of the object
  # @return [AsyncPromise<StorageObjectReadJson>]
  def read_object(id)
    raise NotImplementedError, "Subclasses must implement init"
  end

  # Write an object blob to the simple storage server.
  # the actual http server of this simple storage should hook this method to resolve the `POST` http request at the path `/v1/blobs`, with {@link data} as the body of the request.
  # @param data [StorageObjectWriteJson] The json-like object to write into the storage (consists of `id: String` and `data: Base64String` fields).
  # @return [AsyncPromise<true>]
  def write_object(data)
    raise NotImplementedError, "Subclasses must implement backup"
  end

  # Initialize the frontend's service by initializing all backend the backend storages (by calling their `init` methods).
  # The returned task is supposed to resolve after either a timeout or after all services have initialized (whichever is first).
  # moreover, the implementation should resolve the [is_ready] promise if the initialization was successful.
  # @return [AsyncPromise<void>]
  def init
    raise NotImplementedError, "Subclasses must implement init"
  end

  # Hint all backend socket to initialize a backup process (by calling their `backup` methods).
  # The implementation should set an async scheduler to invoke this method at regular intervals.
  # @return [AsyncPromise<void>]
  def backup
    raise NotImplementedError, "Subclasses must implement backup"
  end

  # Close the frontend access to the storage, and then shutdown all backend storage sockets (by calling their `close` methods).
  # It should also reset the is_ready promise.
  # @return [AsyncPromise<void>]
  def close
    raise NotImplementedError, "Subclasses must implement close"
  end
end


# The writable object that the server's storage frontend expects from the client (in json encoding).
class StorageObjectWriteJson < Struct.new(:id, :data)
  # sanity checks made:
  # - the storage fronted ({@link StorageFrontend}) must check its metadata table to ensure that this id does not already exist in any backends.
  # @return [StorageObjectId] the ID of the object being stored
  attr_accessor :id

  # the base64-encoded data to store in one of the backend storages.
  # sanity checks made:
  # - the storage fronted ({@link StorageFrontend}) must validate that it is decodable, otherwise it should respond to the client with an error.
  # @return [StorageObjectData64] The binary data to store in base64 encoding
  attr_accessor :data

  # @param id [StorageObjectId] the ID of the object being stored
  # @param data [StorageObjectData64] The binary data to store in base64 encoding
  # def initialize(id:, data:)
  #   @id = id
  #   @data = data
  # end
end

# The readable object that the client receives from the server's frontend storage (in json encoding).
class StorageObjectReadJson < Struct.new(:id, :size, :created_at, :data)
  # @return [StorageObjectId] the ID of the object being referenced
  attr_accessor :id

  # @return [Integer] The size of the object in bytes
  attr_accessor :size

  # @return [Integer] The epoch UTC time of object creation, relative to storage server's time of full data acquisition
  attr_accessor :created_at

  # the base64-encoded data stored in one of the backend storages.
  # @return [String] The binary data
  attr_accessor :data

  # @param id [StorageObjectId] the ID of the object being referenced
  # @param size [Integer] The size of the object in bytes
  # @param created_at [Integer] The epoch UTC time of object creation, relative to storage server's time of full data acquisition
  # @param data [StorageObjectData64] The binary data to stored in the backend in base64 encoding
  # def initialize(id:, size:, created_at:, data:)
  #   @id = id
  #   @size = size
  #   @created_at = created_at
  #   @data = data
  # end
end

# The base64-encoded version of StorageObjectData, embeddable in JSON
StorageObjectData64 = String
