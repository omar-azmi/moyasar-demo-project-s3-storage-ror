require "async"
require "async/variable"

# An Asynchronous Promise (of generic type `T`) holds necessary information about what should be executed when the promise is resolved or rejected,
# and which child Promise nodes to propagate the output values of the resolver/rejector to.
class AsyncPromise < Async::Variable
  alias_method :async_resolve, :resolve # rename the `Async::Variable.resolve` instance method to `async_resolve`, since we will be using the same method name for our own logic of resolving values.
  alias_method :async_wait, :wait # rename the `Async::Variable.wait` instance method to `async_wait`, since we will need to tap into the waiting process to raise any errors that may have occurred during the process.

  # @param on_resolve [(value) => next_value_or_promise, nil] the function to call when the promise is resolved with a value.
  # @param on_reject [(reason) => next_value_or_promise, nil] the function to call when the promise is rejected (either manually or due to a raised error).
  def initialize(on_resolve = nil, on_reject = nil)
    super()
    # @type ["pending", "fulfilled", "rejected"] Represents the current state of this Promise node.
    @status = "pending"
    # @type [Array<AsyncPromise>] An array of child [AsyncPromise] nodes that will be notified when this promise resolves.
    #   the resulting structure is a tree-like, and we shall traverse them in DFS (depth first search).
    @children = []
    # @type [Any] the value of type `T` that will be assigned to this node when it resolves.
    #   this value is kept purely for the sake of providing latecomer-then calls with a resolve value (if the `@status` was "fulfilled")
    #   a latecomer is when a call to the [then] or [catch] method is made after the promise has already been "fulfilled".
    @value = nil
    # @type [String, StandardError] the error reason that will be assigned to this node when it is rejected.
    #   this value is kept purely for the sake of providing latecomer-then calls with a rejection reason (if the `@status` was "rejected")
    #   a latecomer is when a call to the [then] or [catch] method is made after the promise has already been "rejected".
    @reason = nil
    @on_resolve = on_resolve
    @on_reject = on_reject
  end

  # Create a new AsyncPromise that is already resolved with the provided [value] of type `T`.
  # @param value [T, AsyncPromise<T>] Generic value of type `T`.
  # return [AsyncPromise<T>] The newly created (and resolved) promise is returned.
  # TODO: create unit test, and maybe reduce the amount of pre-resolved promises you create in your tests through the use of this
  def self.resolve(value = nil)
    new_promise = new()
    new_promise.resolve(value)
    new_promise
  end

  # Create a new AsyncPromise that is already rejected with the provided [reason].
  # WARNING: Do not pass a `nil` as the reason, because it will break the error handling logic, since it will seem to it like there was no error.
  # @param reason [String, StandardError] Give the reason for rejection.
  # return [AsyncPromise<nil>] The newly created (and rejected) promise is returned.
  # TODO: create unit test, and maybe reduce the amount of pre-resolved rejects you create in your tests through the use of this
  def self.reject(reason = "AsyncPromise error")
    new_promise = new()
    new_promise.reject(reason)
    new_promise
  end

  # Create a new AsyncPromise that resolves when all of its input promises have been resolved, and rejects when any single input promise is rejected.
  # @param promises [Array<[T, AsyncPromise<T>]>] Provide all of the input AsyncPromise<T> to wait for, in order to resolve.
  # return [AsyncPromise<Array<T>>] Returns a Promise which, when resolved, contains the array of all resolved values.
  # TODO: create unit test
  def self.all(promises = [])
    # we must return early on if no promises we given, since nothing will then resolve the new_promise.
    return self.resolve([]) if promises.empty?

    new_promise = new()
    resolved_values = []
    remaining_promises = promises.length

    # The following may not be the prettiest implementation. TODO: consider if you can use a Array.map for this function
    promises.each_with_index do |promise, index|
      promise.then(->(value) {
        resolved_values[index] = value
        remaining_promises -= 1
        if remaining_promises == 0
          new_promise.resolve(resolved_values)
        end
      }, ->(reason) {
        # if there is any rejected dependency promise, we should immediately reject our new_promise
        # note that this is somewhat of a error-racing scenario, since the new promise will be rejected due to the first error it encounters.
        # i.e. its order can vary from time to time, possibly resulting in different kinds of rejection reasons
        new_promise.reject(reason)
      })
    end
    new_promise
  end

  # TODO: implement `AsyncPromise.allSettled` static method

  # Resolve the value of this AsyncPromise node.
  # @param value [T, AsyncPromise<T>] Generic value of type `T`.
  # return [void] nothing is returned.
  def resolve(value = nil)
    return nil if @status != "pending" # if the promise is already fulfilled or rejected, return immediately

    Async do |task|
      if value.is_a?(AsyncPromise)
        # if the provided value itself is a promise, then this (self) promise will need to become dependant on it.
        value.then(
          ->(resolved_value) { self.resolve(resolved_value); resolved_value },
          ->(rejection_reason) { self.reject(rejection_reason); rejection_reason },
        )
      else
        # otherwise, since we have an actual resolved value at hand, we may now pass it onto the dependent children.
        begin
          value = @on_resolve.nil? \
            ? value
            : @on_resolve.call(value) # it's ok if `@on_resolve` returns another promise object, because the children will then lach on to its promise when their `resolve` method is called.
        rescue => error_reason
          # some uncaught error occurred while running the `@on_resolve` function. we should now reject this (self) promise, and pass the responsibility of handling to the children (if any).
          self.handle_imminent_reject(error_reason)
        else
          # no errors occurred after running the `@on_resolve` function. we may now resolve the children.
          self.handle_imminent_resolve(value)
        end
      end
    end

    nil
  end

  # Reject the value of this AsyncPromise node with an optional error reason.
  # WARNING: Do not pass a `nil` as the reason, because it will break the error handling logic, since it will seem to it like there was no error.
  # @param reason [String, StandardError] The error to pass on to the next series of dependant promises.
  # return [void] nothing is returned.
  def reject(reason = "AsyncPromise error")
    return nil if @status != "pending" # if the promise is already fulfilled or rejected, return immediately

    Async do |task|
      # since there has been an error, we must call the `@on_reject` method to see if it handles it appropriately (by not raising another error and giving a return value).
      # if there is no `on_reject` available, we will just have to continue with the error propagation to the children.
      if @on_reject.nil?
        # no rejection handler exists, thus the children must bear the responsibility of handling the error
        self.handle_imminent_reject(reason)
      else
        # an `@on_reject` handler exists, so lets see if it can reolve the current error with a value.
        new_handled_value = nil
        begin
          new_handled_value = @on_reject.call(reason)
        rescue => new_error_reason
          # a new error occurred in the `@on_reject` handler, resulting in no resolvable value.
          # we must now pass on the responsibility of handling it to the children.
          self.handle_imminent_reject(new_error_reason)
        else
          # the `@on_reject` function handled the error appropriately and returned a value, so we may now resolve the children with that new value.
          self.handle_imminent_resolve(new_handled_value)
        end
      end
    end

    nil
  end

  # @param on_resolve [(value) => next_value_or_promise, nil] the function to call when the promise is resolved with a value.
  # @param on_reject [(reason) => next_value_or_promise, nil] the function to call when the promise is rejected (either manually or due to a raised error).
  # @return [AsyncPromise] returns a new promise, so that multiple [then] and [catch] calls can be chained.
  def then(on_resolve = nil, on_reject = nil)
    chainable_promise = self.class.new(on_resolve, on_reject)

    Async do |task|
      case @status
      when "pending"
        # add the new promise as a child to the currently pending promise. once this promise resolves, the new child will be notified.
        @children << chainable_promise
      when "fulfilled"
        # this promise has already been fulfilled, so the child must be notified of the resolved value immediately.
        chainable_promise.resolve(@value)
      when "rejected"
        # this promise has already been rejected, so the child must be notified of the rejection reason immediately.
        chainable_promise.reject(@reason)
      end
    end

    chainable_promise
  end

  # A catch method is supposed to rescue any rejections that are made by the parent promise.
  # it is syntactically equivalent to a `self.then(nil, on_reject)` call.
  # @param on_reject [(reason) => next_value_or_promise, nil] the function to call when the promise is rejected (either manually or due to a raised error).
  # @return [AsyncPromise] returns a new promise, so that multiple [then] and [catch] calls can be chained.
  def catch(on_reject = nil)
    self.then(nil, on_reject)
  end

  # Wait for the Promise to be resolved, or rejected.
  # If the Promise was rejected, and you wait for it, then it will raise an error, which you will have to rescue externally.
  # @returns [Any] The resolved value of type `T`.
  # @raise [String, StandardError] The error/reason for the rejection of this Promise.
  def wait
    value = self.async_wait()
    unless @reason.nil?
      # if an error had existed for this promise, then we shall raise it now.
      raise @reason
    end
    value
  end

  # Get the status of the this Promise.
  # This should be used for debugging purposes only. your application logic MUST NOT depend on it, at all.
  # @return ["pending", "fulfilled", "rejected"] Represents the current state of this Promise node.
  def status
    @status
  end

  # Provide a final resolved value for this promise node.
  # @param value [Any] the final resolved value to commit to.
  private def handle_imminent_resolve(value)
    @status = "fulfilled"
    @value = value
    Async do |task|
      @children.each { |child_promise| child_promise.resolve(value) }
    end
    self.async_resolve(value)  # Ensure the underlying `Async::Variable` is resolved, so that the async library can stop waiting for it.
    nil
  end

  # Provide a final rejection reason/error for this promise node.
  # @param value [String, StandardError] the final error/reason for rejection to commit to.
  private def handle_imminent_reject(reason)
    @status = "rejected"
    @reason = reason
    # we are not going to raise the error here, irrespective of whether or not child promises are available.
    # the error is intended to be ONLY risen when a rejected promise is awaited for via our overloaded `wait` method.
    unless @children.empty?
      # if there are child promises, we will pass the reason for rejection to each of them (and each must handle it, otherwise error exceptions will be raised when they are awaited for).
      Async do |task|
        @children.each { |child_promise| child_promise.reject(reason) }
      end
    end
    self.async_resolve(nil)  # Ensure the underlying `Async::Variable` is resolved with a `nil`, so that the async library can stop waiting for it.
    nil
  end
end
