require "./lib/helpers/async_promise"

# Configure the Async logger to always be disabled, so that it does not log unhandled errors that are supposed to bubble up to the parent reactor.
# To disable logging at a later time, simply call `Console.logger.clear(Async::Task)`
# TODO: This is no longer necessary, since I will be using my `AsyncPromise` construct for Asynchronous tasks, which gives the potential to handle rejected promises.
#       Thus, no uncaught error should ever bubble to the top if you make sure that all promise actions are capable of catching exceptions or if you make sure to wait inside a `begin-rescue` block.
# Console.logger.disable(Async::Task)

# Backend sockets must use this custom exception for backend network originated errors
class BackendNetworkError < StandardError
end

### StorageBackendSocket abstract base class.
# This class defines the interface that all storage backends must implement.
#
# Storage Server overview:
#
#   Client1-----┐         ┌────────────┐◄────────►-----S3
#               │         │            │
#   Client2-----┤         │   Simple   │
#               ◄────────►│   Storage  │◄────────►-----DB
#   Client3-----┤Frontend │   Server   │
#               │Socket   │            │
#   Client4-----┘Interface└────────────┘◄────────►-----FS
#                                     Backend Socket
#                                       Interfaces
#
# @abstract Subclasses must implement all abstract methods.
class StorageBackendSocket
  # This promise is resolved to a [true] value when the backend storage server is ready to take requests.
  # Otherwise, if it has resolved to [false], then the server is unavailable (possibly failed to initialize).
  # While the promise/task is pending, the server might still be loading.
  # @return [AsyncPromise<Boolean>]
  attr_accessor :is_ready

  # Initialize the backend storage server (if it isn't already running).
  # The returned task is supposed to resolve after it is ready.
  # moreover, the implementation should resolve the [is_ready] task if the initialization was successful.
  # @return [AsyncPromise<void>]
  def init
    raise NotImplementedError, "Subclasses must implement init"
  end

  # Perform a backup of the current state of the backend storage.
  # This should be called at regular intervals by the frontend server holding this socket.
  # @return [AsyncPromise<void>]
  def backup
    raise NotImplementedError, "Subclasses must implement backup"
  end

  # Close the backend storage server, perform a backup, and shut it down.
  # It should also reset the is_ready promise.
  # @return [AsyncPromise<void>]
  def close
    raise NotImplementedError, "Subclasses must implement close"
  end

  # Check if the backend storage is currently available.
  # @return [AsyncPromise<number>] Latency time in milliseconds
  def is_online
    raise NotImplementedError, "Subclasses must implement is_online"
  end

  # Retrieve the metadata of a storage object by its ID.
  # This might also be used by the frontend of the storage to confirm the existence of data tied to an ID.
  # @param id [StorageObjectId] The ID of the object
  # @return [AsyncPromise<StorageObjectMetadata>]
  def get_object_metadata(id)
    raise NotImplementedError, "Subclasses must implement get_object_metadata"
  end

  # Check whether the backend approves storing an object with the provided metadata stats.
  # @param stats [StorageObjectMetadata] The metadata stats for the object
  # @return [AsyncPromise<boolean>] Whether the backend approves the storage of the object
  def approve_object_metadata(stats)
    raise NotImplementedError, "Subclasses must implement approve_object_metadata"
  end

  # Retrieve an object blob by its ID from the backend storage.
  # @param id [StorageObjectId] The ID of the object
  # @return [AsyncPromise<StorageObjectData>]
  def get_object(id)
    raise NotImplementedError, "Subclasses must implement get_object"
  end

  # Store an object blob in the backend storage.
  # @param id [StorageObjectId] The ID of the object
  # @param data [StorageObjectData] The blob data to store
  # @return [AsyncPromise<StorageObjectMetadata>]
  def set_object(id, data)
    raise NotImplementedError, "Subclasses must implement set_object"
  end
end

# The unique identifier for any storage object
StorageObjectId = String

# The raw data blob of any storage object
StorageObjectData = String # or Binary/IO, depending on how the data will be handled

# Metadata for storage objects
class StorageObjectMetadata < Struct.new(:id, :size, :created_at)
  # @return [StorageObjectId] the ID of the object being referenced
  attr_accessor :id

  # @return [Integer] The size of the object in bytes
  attr_accessor :size

  # @return [Integer] The epoch UTC time of object creation, relative to storage server's time of full data acquisition
  attr_accessor :created_at

  # @param id [StorageObjectId] the ID of the object being referenced
  # @param size [Integer] The size of the object in bytes
  # @param created_at [Integer] The epoch UTC time of object creation, relative to storage server's time of full data acquisition
  # def initialize(id:, size:, created_at:)
  #   @id = id
  #   @size = size
  #   @created_at = created_at
  # end
end
