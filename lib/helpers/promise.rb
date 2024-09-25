
# A [PromiseThenNode] (of generic type `T`) holds necessary information about what should be executed when the promise is resolved or rejected,
# and which child Promise nodes to propagate the output values of the resolver/rejector to/
class PromiseThenNode
  # @param on_resolve [(value) => next_value_or_promise, nil] the function to call when the promise is resolved with a value
  # @param on_reject [(reason) => next_value_or_promise, nil] the function to call when the promise is rejected (either manually or due to a raised error)
  def initialize(on_resolve = nil, on_reject = nil)
    # @type ["pending", "fulfilled", "rejected"] Represents the current state of this Promise node.
    @status = "pending"
    # @type [Array<PromiseThenNode>] An array of child Promise nodes that will be notified when this promise resolves.
    #   the resulting structure is a tree-like, and we shall traverse them in DFS (depth first search).
    @children = []
    # the value of type `T` that will be assigned to this node when it resolves.
    #   this value is kept purely for the sake of providing latecomer-then calls with a resolve value (if the `@status` was "fulfilled")
    #   a latecomer is when a call to the [then] or [catch] method is made after the promise has already been "fulfilled".
    @value = nil
    # the error reason that will be assigned to this node when it is rejected.
    #   this value is kept purely for the sake of providing latecomer-then calls with a rejection reason (if the `@status` was "rejected")
    #   a latecomer is when a call to the [then] or [catch] method is made after the promise has already been "rejected".
    @reason = nil
    @on_resolve = on_resolve
    @on_reject = on_reject
  end

  # Resolve the value of this Promise node.
  # @param value [Any, PromiseThenNode<Any>] Generic value of type `T`.
  # return [void] nothing is returned
  def resolve(value)
    return nil if @status != "pending"

    if value.is_a?(PromiseThenNode)
      # if the provided value itself is a promise, then this (self) promise will need to become dependant on it.
      value.then(
        ->(resolved_value) { self.resolve(resolved_value); resolved_value },
        ->(rejection_reason) { self.reject(rejection_reason); rejection_reason },
      )
    else
      # otherwise, since we have an actual resolved value at hand, we may now pass it onto the dependent children.
      error_reason = nil
      begin
        value = @on_resolve.nil? \
          ? value
          : @on_resolve.call(value) # it's ok if `@on_resolve` returns another promise object, because the children will then lach on to its promise when their `resolve` method is called.
      rescue => err
        error_reason = err
      end
      if error_reason.nil?
        # no errors occurred after running the `@on_resolve` function. we may now resolve the children.
        self.handle_imminent_resolve(value)
        # @status = "fulfilled"
        # @value = value
        # @children.each(->(child_promise) { child_promise.resolve(value) })
      else
        # some uncaught error occurred while running the `@on_resolve` function. we should now reject this (self) promise, and pass the responsibility of handling to the children (if any).
        self.handle_imminent_reject(error_reason)
        # TODO: the technique commented below will be problematic, because it means that errors will flow from `on_resolve` to `on_reject` adjacently,
        #       so overall it will look like a zigzag. but in reality, the flow should be like a criscross/diagonals and straight lines.
        # self.reject(error_reason)
      end
    end
    nil
  end

  # Reject the value of this Promise node with an optional error reason.
  # @param reason [String, StandardError] The error to pass on to the next series of dependant promises.
  # return [void] nothing is returned
  def reject(reason = "Promise error")
    return nil if @status != "pending"

    # since there has been an error, we must call the `@on_reject` method to see if it handles it appropriately (by not raising another error and giving a return value).
    # if there is no `on_reject` available, we will just have to continue with the error propagation to the children.
    new_error_reason = nil
    new_handled_value = nil
    begin
      if @on_reject.nil?
        new_error_reason = reason
      else
        new_handled_value = @on_reject.call(reason)
      end
    rescue => err
      new_error_reason = err
    end

    # we will now see if a new value has been acquired, or if the error persisted
    if new_error_reason.nil?
      # the `@on_reject` function handled the error appropriately and returned a value, so we may now resolve the children with that new value
      self.handle_imminent_resolve(new_handled_value)
      # @status = "fulfilled"
      # @value = new_handled_value
      # @children.each(->(child_promise) { child_promise.resolve(value) })
    else
      # the error persisted, and we must now pass on the responsibility of handling it
      self.handle_imminent_reject(new_error_reason)
      # @status = "rejected"
      # @reason = new_error_reason
      # if @children.empty?
      #   # if there are no children to pass on the responsibility of handing the error, then we must raise it at the global scope, since it is an unhandled error.
      #   raise new_error_reason
      # else
      #   # otherwise, we will pass the reason for rejection onto each dependent children (and each must handle it otherwise error exceptions will be raised).
      #   @children.each(->(child_promise) { child_promise.reject(new_error_reason) })
      # end
    end
    nil
  end

  # @param on_resolve [(value) => next_value_or_promise, nil] the function to call when the promise is resolved with a value
  # @param on_reject [(reason) => next_value_or_promise, nil] the function to call when the promise is rejected (either manually or due to a raised error)
  # @return [PromiseThenNode] returns a new promise, so that multiple [then] and [catch] calls can be chained.
  def then(on_resolve = nil, on_reject = nil)
    chainable_promise = self.class.new(on_resolve, on_reject)
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
    chainable_promise
  end

  # A catch method is supposed to rescue any rejections that are made by the parent promise.
  # it is syntactically equivalent to a `self.then(nil, on_reject)` call.
  # @param on_reject [(reason) => next_value_or_promise, nil] the function to call when the promise is rejected (either manually or due to a raised error).
  # @return [PromiseThenNode] returns a new promise, so that multiple [then] and [catch] calls can be chained.
  def catch(on_reject = nil)
    self.then(nil, on_reject)
  end

  def status
    @status
  end

  private def handle_imminent_resolve(value)
    @status = "fulfilled"
    @value = value
    @children.each { |child_promise| child_promise.resolve(value) }
    nil
  end

  private def handle_imminent_reject(reason)
    @status = "rejected"
    @reason = reason
    if @children.empty?
      # if there are no children to pass on the responsibility of handling the error, then we must raise it at the global scope, since it is an unhandled error.
      raise reason
    else
      # otherwise, we will pass the reason for rejection onto each dependent children (and each must handle it otherwise error exceptions will be raised).
      @children.each { |child_promise| child_promise.reject(reason) }
    end
    nil
  end
end

# a = PromiseThenNode.new

# b = a.then(->(v) { puts "1 #{v}" }, ->(v) { puts "2 #{v}" })
