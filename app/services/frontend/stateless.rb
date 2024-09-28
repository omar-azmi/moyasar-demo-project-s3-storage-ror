require "base64"
require_relative "./base"

# This frontend of the simple storage server stores user payload data in randomly picked backend storage.
# And for reading back the data, it queries every backend storage socket if they have the id stored with them.
# As a result, it itself does not need to store metadata of the objects it has processed, which is why we call it stateless.
# The backend sockets it holds still have a states, and thus are obviously not stateless.
class StatelessFrontendSocket < StorageFrontendSocket
  # Initialize the frontend storage, managing multiple backend storage sockets.
  # @param backend_sockets [Array<StorageBackendSocket>] The backend storage sockets to manage.
  def initialize(backend_sockets)
    super()
    @sockets = backend_sockets
    self.is_ready = AsyncPromise.new()
    # TODO: this currently requires manual initialization, because otherwise auto initialization breaks the StatefulFrontendSocket subclass.
    #       find a better way of managing auto initialization, or maybe ditch it and always require manual initialization.
    # StatelessFrontendSocket.instance_method(:init).bind(self).call()
    # self.init()
  end

  # Initialize all backend storage sockets and ensure they are ready.
  # @return [AsyncPromise<void>]
  def init
    self.is_ready = AsyncPromise.new()
    init_promises = @sockets.map do |socket|
      socket.init
        .then(->(_) { socket.is_ready.wait })
        .catch(->(reason) {
          # it is ok if one or more backend sockets are not available. we will silently ignore it.
          # the frontend is supposed to be tolerant of non-ready backends.
          puts "Backend failed to initialize: #{reason.message}"
        })
    end
    # Wait for all backends to initialize or timeout
    AsyncPromise.all(init_promises)
      .then(->(_) { self.is_ready.resolve(true) })
      .catch(->(reason) { self.is_ready.reject(FrontendNetworkError.new(reason)) })
  end

  # Trigger a backup process across all backend sockets.
  # @return [AsyncPromise<void>]
  def backup
    backup_promises = @sockets.map { |socket| socket.backup }
    AsyncPromise.all(backup_promises)
  end

  # Close the frontend and all backend storage sockets.
  # @return [AsyncPromise<void>]
  def close
    self.is_ready = AsyncPromise.reject(FrontendNetworkError.new("Frontend has been closed."))
    # first do a backup, and then close all backend sockets
    self.backup()
      .then(->(_) {
        close_promises = @sockets.map { |socket| socket.close }
        AsyncPromise.all(close_promises).wait
        nil
      })
  end

  # Read an object from the storage.
  # It will search through all backend sockets to find the object.
  # @param id [String] The ID of the object to read.
  # @param sockets [Array<Integer>] The indexes of sockets to try reading the `id` from concurrently.
  #        By default, it is the index of all available sockets.
  # @return [AsyncPromise<[nil, StorageObjectReadJson]>]
  def read_object(id, sockets: nil)
    sockets = sockets || [ *(0...(@sockets.length)) ]
    read_promises = sockets.map do |index|
      socket = @sockets[index]
      socket.get_object_metadata(id).then(->(metadata) {
        socket.get_object(id).then(->(data) {
          StorageObjectReadJson.new(
            id: metadata[:id],
            size: metadata[:size],
            created_at: metadata[:created_at],
            data: Base64.strict_encode64(data),
          )
        })
      }).catch(->(_) { nil })
    end

    self.is_ready.then(->(_) {
      AsyncPromise.all(read_promises).then(->(results) {
        # return the first non nil result
        results.each { |result|
          return result unless result.nil?
        }
        # if all results are nil, then we will return a nil, and log a warning. I do not want to raise an error here
        puts FrontendNetworkError.new("Object not found in any backend")
        nil
      })
    })
  end

  # Write an object to a randomly picked backend socket (which must be online).
  # @param payload [StorageObjectWriteJson] The payload of the object data that needs to be stored.
  # @param sockets [Array<Integer>] The indexes of sockets to pick from to store the payload.
  #        If one is unavailable, the next one will be tried.
  #        By default, it shuffles the indexes of all available sockets, and then tries each for storage.
  # @return [AsyncPromise<Integer>] the return value reflects which backend socket took in our data. it will be `-1` if the writing was unsuccessful.
  def write_object(payload, sockets: nil)
    sockets = sockets || [ *(0...(@sockets.length)) ].shuffle()
    self.is_ready.then(->(_) {
      # we first create a shuffled version of our sockets array,
      # and then we synchronously check if each socket is online and ready to take the data.
      # if the first backend that is online AND refuses to accept the data/id, then it means that the id is already registered and cannot be updated
      # in such case, we will terminate any further checks and return a `-1`.
      # otherwise the first online socket accepts the data, then we may send it that data and finally return the `index` of the storage
      data_blob = nil # for caching the blob data in case we decode the base64 encoded data at some point
      sockets.each do |index|
        socket = @sockets[index]
        unless (socket.is_online().wait() rescue nil).nil?
          if data_blob.nil?
            begin data_blob = Base64.strict_decode64(payload["data"])
            rescue
              puts FrontendNetworkError.new("The given id \"#{payload["id"]}\" in the payload is already stored.")
              return -1
            end
          end

          socket_approval = socket.approve_object_metadata({ id: payload["id"], size: data_blob.bytesize }).wait() rescue false
          if socket_approval == true
            socket.set_object(payload["id"], data_blob).wait()
            return index
          end
          puts FrontendNetworkError.new("The given id \"#{payload["id"]}\" in the payload is already stored.")
          return -1
        end
      end
      puts FrontendNetworkError.new("No backend is currently online to store payload with id: \"#{payload["id"]}\".")
      -1
    })
  end
end
