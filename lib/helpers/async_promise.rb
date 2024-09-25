require "async"
require "async/variable"

# An Asynchronous Promise (of generic type `T`) holds necessary information about what should be executed when the promise is resolved or rejected,
# and which child Promise nodes to propagate the output values of the resolver/rejector to.
class AsyncPromise < Async::Variable
  alias_method :async_resolve, :resolve # rename the `Async::Variable.resolve` instance method to `async_resolve`, since we will be using the same method name for our own logic of resolving values.

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
    # @type [String | StandardError] the error reason that will be assigned to this node when it is rejected.
    #   this value is kept purely for the sake of providing latecomer-then calls with a rejection reason (if the `@status` was "rejected")
    #   a latecomer is when a call to the [then] or [catch] method is made after the promise has already been "rejected".
    @reason = nil
    @on_resolve = on_resolve
    @on_reject = on_reject
  end

  # TODO: consider adding `self.resolve` and `self.reject` class static methods to `Promise`, such that calling `Promise.reject` will not
  #       immediately raise an error to the top (i.e. we will rescue it within the method's block, so that it doesn't bubble outside to the top)

  # Resolve the value of this AsyncPromise node.
  # @param value [Any, AsyncPromise<Any>] Generic value of type `T`.
  # return [void] nothing is returned.
  def resolve(value)
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
    Async do |task|
      if @children.empty?
        # if there are no children to pass on the responsibility of handling the error, then we must raise it at the global scope, since it is an unhandled error.
        raise reason
      else
        # otherwise, we will pass the reason for rejection onto each dependent children (and each must handle it otherwise error exceptions will be raised).
        @children.each { |child_promise| child_promise.reject(reason) }
      end
    end
    self.async_resolve(reason)  # Ensure the underlying `Async::Variable` is resolved, so that the async library can stop waiting for it.
    nil
  end
end



# example usage
# Async do
#   p1 = AsyncPromise.new
#   p2 = p1.then(->(v) { puts "Resolved to #{v}"; "Next Value" })
#          .catch(->(e) { puts "Caught error: #{e}" })

#   # resolving the promise asynchronously
#   Async do
#     sleep 1
#     p1.reject("First Error")
#     p1.resolve("Second Value")
#     p1.reject("Third Error")
#   end

#   # waiting for the result
#   p2.wait # prints "Caught error: First Error"
# end
