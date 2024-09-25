require "rspec"
require "time"
require "./lib/helpers/async_promise"

RSpec.describe AsyncPromise do
  ### Testing for Synchronous behavior, to verify control flow
  context "Synchronous Resolution Behavior" do
    it "should resolve with a value" do
      final_value = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1.then(->(v) { final_value = v; v })
        promise1.resolve("Success")
        expect(final_value).to eq("Success")
        expect(promise2.wait).to eq("Success")
        expect(promise1.wait).to eq("Success")
      end
    end

    it "should chain multiple thens and propagate resolved values" do
      final_value = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1
          .then(->(v) { "#{v} World" })
          .then(->(v) { "#{v}!" })
          .then(->(v) { final_value = v; v })
        promise1.resolve("Hello")
        expect(promise2.wait).to eq("Hello World!")
      end
      expect(final_value).to eq("Hello World!")
    end

    it "should resolve immediately for latecomer then calls after promise is resolved" do
      final_value = nil
      Async do
        promise = AsyncPromise.new
        promise.resolve("Already Resolved")
        expect(promise.then(->(v) { final_value = v }).wait).to eq("Already Resolved")
      end
      expect(final_value).to eq("Already Resolved")
    end

    it "should handle promise returned in then block" do
      final_value = nil
      Async do
        promise = AsyncPromise.new
        inner_promise = AsyncPromise.new
        promise
          .then(->(_) { inner_promise })
          .then(->(v) { final_value = v })

        promise.resolve("Outer Resolved")
        expect(final_value).to be_nil() # because `inner_promise` has not been resolved yet
        inner_promise.resolve("Inner Resolved")
        expect(inner_promise.wait).to eq("Inner Resolved")
      end
      expect(final_value).to eq("Inner Resolved")
    end
  end

  context "Synchronous Rejection Behavior" do
    it "should reject with an error" do
      reason = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1.catch(->(e) { reason = e; nil })
        promise1.reject("Rejected!")
        expect(promise2.wait).to be_nil()
      end
      expect(reason).to eq("Rejected!")
    end

    it "should reject immediately for latecomer then calls, after the promise has already been rejected" do
      reason = nil
      Async do
        promise1 = AsyncPromise.new
        promise1.reject("Already Rejected!")
        expect { promise1.wait }.to raise_error("Already Rejected!")
        promise2 = promise1.catch(->(e) { reason = e; nil })
        expect(reason).to eq("Already Rejected!") # the new value should get assigned even before we wait for promise2, because its dependency, promise1, has already completed execution (rejected)
        expect(promise2.wait).to be_nil()
        expect { promise1.wait }.to raise_error("Already Rejected!") # waiting for a failed promise again should raise the error again.
      end
      expect(reason).to eq("Already Rejected!")
    end

    it "should propagate rejection through then chains" do
      reason = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1
          .then(->(v) { "#{v} World" })
          .catch(->(e) { reason = e; nil })
        promise1.reject("Error occurred")
        expect(promise2.wait).to be_nil()
      end
      expect(reason).to eq("Error occurred")
    end

    it "should propagate error originating inside of the promise chain, through the upcoming chained promises" do
      reason = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1
          .then(->(_) { raise "Another Error" })
          .catch(->(e) { reason = e; nil })
        promise1.resolve("Initial")
        expect(promise2.wait).to be_nil()
      end
      expect(reason.message).to eq("Another Error")
    end

    it "should recover from rejection in catch and propagate resolved value" do
      final_value = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1
          .then(->(v) { raise "Failure" })
          .catch(->(e) { "Recovered" })
          .then(->(v) { final_value = v; v })
        promise1.resolve("Initial Value")
        expect(promise2.wait).to eq("Recovered")
      end
      expect(final_value).to eq("Recovered")
    end
  end

  context "Edge Cases" do
    it "should not allow resolution after rejection" do
      value = nil
      reason = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1.then(->(v) { value = v; v }, ->(e) { reason = e; e })
        promise1.reject("First Rejection")
        promise1.resolve("Attempt to resolve after rejection")
        expect(promise2.wait).to eq("First Rejection")
      end
      expect(value).to be_nil()
      expect(reason).to eq("First Rejection")
    end

    it "should not allow rejection after resolution" do
      value = nil
      reason = nil
      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1.then(->(v) { value = v; v }, ->(e) { reason = e; e })
        promise1.resolve("First Resolution")
        promise1.reject("Attempt to reject after resolution")
        expect(promise2.wait).to eq("First Resolution")
      end
      expect(value).to eq("First Resolution")
      expect(reason).to be_nil()
    end

    it "should throw error for unhandled rejections when they are waited for" do
      Async do
        promise = AsyncPromise.new
        promise.reject("Unhandled Rejection")
        # the error gets risen only after we call the wait method
        expect { promise.wait }.to raise_error("Unhandled Rejection")
        end
    end
  end


  ### Testing static methods of the class
  context "Static Methods" do
    describe "AsyncPromise.resolve" do
      it "creates a promise that resolves immediately with a given value" do
        result = nil
        Async do
          promise = AsyncPromise.resolve("Resolved Value")
          promise.then(->(v) { result = v }).wait
        end
        expect(result).to eq("Resolved Value")
      end

      it "handles a resolved AsyncPromise passed into .resolve" do
        result = nil
        Async do
          inner_promise = AsyncPromise.resolve("Inner Resolved")
          promise = AsyncPromise.resolve(inner_promise)
          promise.then(->(v) { result = v }).wait
        end
        expect(result).to eq("Inner Resolved")
      end

      it "handles a nil value in .resolve" do
        result = "not_nil"
        Async do
          promise = AsyncPromise.resolve(nil)
          promise.then(->(v) { result = v }).wait
        end
        expect(result).to be_nil
      end
    end

    describe "AsyncPromise.reject" do
      it "creates a promise that rejects immediately with a given reason" do
        rejection_reason = nil
        Async do
          promise = AsyncPromise.reject("Rejection Reason")
          promise.catch(->(e) { rejection_reason = e }).wait
        end
        expect(rejection_reason).to eq("Rejection Reason")
      end

      it "handles rejection of an AsyncPromise in .reject" do
        rejection_reason = nil
        Async do
          promise = AsyncPromise.reject(StandardError.new("Error occurred"))
          promise.catch(->(e) { rejection_reason = e.message }).wait
        end
        expect(rejection_reason).to eq("Error occurred")
      end
    end

    describe "AsyncPromise.all" do
      it "resolves when all promises resolve, and maintains the order of the promises" do
        Async do
          # Resolve all promises in different orders
          p1 = AsyncPromise.resolve("Value 1").then(->(v) { sleep 0.3; v })
          p2 = AsyncPromise.resolve("Value 2").then(->(v) { sleep 0.1; v })
          p3 = AsyncPromise.resolve("Value 3").then(->(v) { sleep 0.2; v })
          p4 = AsyncPromise.all([ p1, p2, p3 ])
          expect(p4.wait).to eq([ "Value 1", "Value 2", "Value 3" ])
        end
      end

      it "rejects if any promise rejects" do
        rejection_reason = nil
        Async do
          # Resolve two, reject one
          p1 = AsyncPromise.resolve("Value 1").then(->(v) { sleep 0.1; v })
          p2 = AsyncPromise.reject("Rejection Reason").catch(->(e) { sleep 0.3; raise e })
          p3 = AsyncPromise.resolve("Value 3").then(->(v) { sleep 0.2; v })
          p4 = AsyncPromise.all([ p1, p2, p3 ]).catch(->(reason) { rejection_reason = reason.message; raise reason })
          expect { p4.wait }.to raise_error("Rejection Reason")
        end
        expect(rejection_reason).to eq("Rejection Reason")
      end

      it "handles an empty array of promises and resolves immediately" do
        result = nil
        Async do
          p1 = AsyncPromise.all([])
          p2 = p1.then(->(values) { result = values })
          expect(result).to eq([]) # the value should be resolved even before we begin to wait
          expect(p2.wait).to eq([])
        end
      end

      it "handles already resolved promises in .all" do
        result = nil
        Async do
          p1 = AsyncPromise.resolve("Resolved 1")
          p2 = AsyncPromise.resolve("Resolved 2")
          p3 = AsyncPromise.resolve("Resolved 3")
          p4 = AsyncPromise.all([ p1, p2, p3 ]).then(->(values) { result = values })
          expect(result).to eq([ "Resolved 1", "Resolved 2", "Resolved 3" ]) # the value should be resolved even before we begin to wait
          expect(p4.wait).to eq([ "Resolved 1", "Resolved 2", "Resolved 3" ])
        end
      end

      it "immediately rejects if any of the promises are already rejected" do
        rejection_reason = nil
        Async do
          p1 = AsyncPromise.resolve("Resolved 1")
          p2 = AsyncPromise.reject("Immediate Rejection")
          p3 = AsyncPromise.resolve("Resolved 3")
          p4 = AsyncPromise.all([ p1, p2, p3 ]).catch(->(reason) { rejection_reason = reason; raise reason })
          expect(rejection_reason).to eq("Immediate Rejection") # the value should be rejected, even before we begin to wait
          expect { p4.wait }.to raise_error("Immediate Rejection")
        end
      end
    end
  end


  ### Testing for Asynchronous behavior
  context "Asynchronous Behavior" do
    it "should resolve two independent promises concurrently" do
      delta_time = Time.now

      Async do
        promise1 = AsyncPromise.new
        promise2 = AsyncPromise.new

        Async do
          sleep 1  # Simulates a long-running task
          promise1.resolve("Promise 1 Resolved")
        end
        Async do
          sleep 0.5  # Simulates a shorter task
          promise2.resolve("Promise 2 Resolved")
        end

        # Waiting for both promises to resolve
        expect(promise1.wait).to eq("Promise 1 Resolved")
        expect(promise2.wait).to eq("Promise 2 Resolved")
        delta_time = Time.now - delta_time
      end
      # Both promises should resolve concurrently, so the total time should be about 1 second
      expect(delta_time).to be_between(1.0, 1.2).inclusive
    end

    it "should resolve two independent promises concurrently within the `on_resolve` lambda" do
      delta_time = Time.now

      Async do
        promise1 = AsyncPromise.new(->(v) {
          sleep 1  # Simulates a long-running task
          v
        })
        promise2 = AsyncPromise.new(->(v) {
          sleep 0.5  # Simulates a shorter task
          v
        })

        promise1.resolve("Promise 1 Resolved")
        promise2.resolve("Promise 2 Resolved")

        # Waiting for both promises to resolve
        expect(promise1.wait).to eq("Promise 1 Resolved")
        expect(promise2.wait).to eq("Promise 2 Resolved")
        delta_time = Time.now - delta_time
      end
      # Both promises should resolve concurrently, so the total time should be about 1 second
      expect(delta_time).to be_between(1.0, 1.2).inclusive
    end

    it "should resolve promises in a chain sequentially" do
      delta_time = Time.now
      final_value = nil

      Async do
        promise1 = AsyncPromise.new
        promise2 = promise1
          .then(->(v) { sleep 0.5; "#{v} -> Step 1" })
          .then(->(v) { sleep 0.5; "#{v} -> Step 2" })
          .then(->(v) { final_value = v; v })

        Async do
          sleep 0.5
          promise1.resolve("Step 0")
        end

        expect(promise2.wait).to eq("Step 0 -> Step 1 -> Step 2")
        expect(final_value).to eq("Step 0 -> Step 1 -> Step 2")
        delta_time = Time.now - delta_time
      end
      # The total time should be 1.5 seconds (0.5 + 0.5 + 0.5) because we waited for the last promise in the chain
      expect(delta_time).to be_between(1.5, 1.7).inclusive
    end

    it "should exit an async block early, even if there are pending (and un-awaited) chained promises" do
      delta_time = Time.now
      final_value = nil

      Async do
        promise = AsyncPromise.new
        promise
          .then(->(v) { sleep 0.5; "#{v} -> Step 1" })
          .then(->(v) { sleep 0.5; "#{v} -> Step 2" })
          .then(->(v) { final_value = v; v })

        Async do
          sleep 0.5
          promise.resolve("Step 0")
        end

        expect(promise.wait).to eq("Step 0") # since only `promise` is awaited for, and not the chained promises, we should exit early at 0.5 seconds
        expect(final_value).to be_nil()
        delta_time = Time.now - delta_time
      end
      # The total time should be 0.5 seconds, since the children/chained promises are not awaited for
      expect(delta_time).to be_between(0.5, 0.7).inclusive
    end

    it "should run two separate promise chains concurrently" do
      delta_time = Time.now
      final_value_1 = nil
      final_value_2 = nil

      Async do
        # Two independent promise chains
        promise_a = AsyncPromise.new(->(v) { sleep 0.5; v })
        promise_b = AsyncPromise.new(->(v) { sleep 0.7; v })

        promise1 = promise_a
          .then(->(v) { sleep 0.5; "#{v} -> Step 1 (chain 1)" })
          .then(->(v) { final_value_1 = v; v })
        promise2 = promise_b
          .then(->(v) { sleep 0.7; "#{v} -> Step 1 (chain 2)" })
          .then(->(v) { final_value_2 = v; v })

        promise_a.resolve("Start Chain 1")
        promise_b.resolve("Start Chain 2")

        # Wait for both promise chains to finish
        expect(promise1.wait).to eq("Start Chain 1 -> Step 1 (chain 1)")
        expect(final_value_1).to eq("Start Chain 1 -> Step 1 (chain 1)")
        expect(final_value_2).to be_nil()
        expect(Time.now - delta_time).to be_between(1.0, 1.2).inclusive
        expect(promise2.wait).to eq("Start Chain 2 -> Step 1 (chain 2)")
        expect(final_value_2).to eq("Start Chain 2 -> Step 1 (chain 2)")
        expect(Time.now - delta_time).to be_between(1.4, 1.6).inclusive
        delta_time = Time.now - delta_time
      end
      # The total time should be about 1.4 seconds since both promises run concurrently, but the slowest chain takes 1.4 seconds
      expect(delta_time).to be_between(1.4, 1.6).inclusive
    end

    it "should run two separate promise chains concurrently, and should wait for zero seconds for an already resolved promise chain" do
      # This example is exactly like the previous one, except that we `wait` for the chains in opposite order (slower first, faster one second)
      delta_time = Time.now
      final_value_1 = nil
      final_value_2 = nil

      Async do
        # Two independent promise chains
        promise_a = AsyncPromise.new(->(v) { sleep 0.5; v })
        promise_b = AsyncPromise.new(->(v) { sleep 0.7; v })

        promise1 = promise_a
          .then(->(v) { sleep 0.5; "#{v} -> Step 1 (chain 1)" })
          .then(->(v) { final_value_1 = v; v })
        promise2 = promise_b
          .then(->(v) { sleep 0.7; "#{v} -> Step 1 (chain 2)" })
          .then(->(v) { final_value_2 = v; v })

        promise_a.resolve("Start Chain 1")
        promise_b.resolve("Start Chain 2")

        # Wait for both promise chains to finish (wait for the slower one first, and then the faster one should be resolved in zero time delay)
        expect(promise2.wait).to eq("Start Chain 2 -> Step 1 (chain 2)")
        expect(final_value_2).to eq("Start Chain 2 -> Step 1 (chain 2)")
        expect(final_value_1).to eq("Start Chain 1 -> Step 1 (chain 1)") # although `promise1` was not awaited, it should be resolved by this time.
        expect(Time.now - delta_time).to be_between(1.4, 1.6).inclusive
        expect(promise1.wait).to eq("Start Chain 1 -> Step 1 (chain 1)")
        expect(final_value_1).to eq("Start Chain 1 -> Step 1 (chain 1)")
        expect(Time.now - delta_time).to be_between(1.4, 1.6).inclusive
        delta_time = Time.now - delta_time
      end
      # The total time should be about 1.4 seconds since both promises run concurrently, but the slowest chain takes 1.4 seconds
      expect(delta_time).to be_between(1.4, 1.6).inclusive
    end

    it "should handle promise rejection via the `catch` method, asynchronously" do
      delta_time = Time.now
      final_value = nil
      rejection_reason = nil

      Async do
        promise1 = AsyncPromise.new(->(v) { sleep 0.3; v })
        promise2 = promise1
          .then(->(v) { sleep 0.5; raise "Step 1 failed" })
          .catch(->(e) { rejection_reason = e.message; "Recovered" })
          .then(->(v) { final_value = v; v })

        promise1.resolve("Start Chain")
        expect(promise2.wait).to eq("Recovered")
        delta_time = Time.now - delta_time
      end
      # Total time should be about 0.8 seconds (0.3 + 0.5) for resolving and rejecting
      expect(delta_time).to be_between(0.8, 1.0).inclusive
      expect(rejection_reason).to eq("Step 1 failed")
      expect(final_value).to eq("Recovered")
    end

    it "should handle promise rejection via `then` method's `on_rejected` argument, asynchronously" do
      delta_time = Time.now
      final_value = nil
      rejection_reason = nil

      Async do
        promise1 = AsyncPromise.new(->(v) { sleep 0.3; v })
        promise2 = promise1
          .then(->(v) { sleep 0.5; raise "Step 1 failed" })
          .then(nil, ->(e) { rejection_reason = e.message; "Recovered" })
          .then(->(v) { final_value = v; v })

        promise1.resolve("Start Chain")
        expect(promise2.wait).to eq("Recovered")
        delta_time = Time.now - delta_time
      end
      # Total time should be about 0.8 seconds (0.3 + 0.5) for resolving and rejecting
      expect(delta_time).to be_between(0.8, 1.0).inclusive
      expect(rejection_reason).to eq("Step 1 failed")
      expect(final_value).to eq("Recovered")
    end

    it "should raise an error when error is not caught by an awaited promise" do
      delta_time = Time.now
      final_value = nil

      Async do
        promise1 = AsyncPromise.new(->(v) { sleep 0.3; v })
        promise2 = promise1
          .then(->(v) { sleep 0.5; raise "Step 1 failed" })
          .then(->(v) { final_value = v; v }, nil)

        promise1.resolve("Start Chain")
        # uncaught exceptions should only be raised when the promise responsible for handling it is awaiten for.
        expect { promise2.wait }.to raise_error("Step 1 failed")
        delta_time = Time.now - delta_time
      end
      # Total time should be about 0.8 seconds (0.3 + 0.5) for resolving and rejecting
      expect(delta_time).to be_between(0.8, 1.0).inclusive
      expect(final_value).to be_nil()
    end
  end
end
