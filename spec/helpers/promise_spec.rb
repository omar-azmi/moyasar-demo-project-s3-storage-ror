require "./lib/helpers/promise"

RSpec.describe Promise do
  context "Promise Resolution" do
    it "should resolve with a value" do
      resolved_value = nil
      promise = Promise.new
      promise.then(->(v) { resolved_value = v })
      promise.resolve("Success")
      expect(resolved_value).to eq("Success")
    end

    it "should propagate resolved value through chain of thens" do
      final_value = nil
      promise = Promise.new
      promise
        .then(->(v) { "#{v} World" })
        .then(->(v) { "#{v}!" })
        .then(->(v) { final_value = v })
      promise.resolve("Hello")
      expect(final_value).to eq("Hello World!")
    end

    it "should allow latecomer to get the resolved value" do
      final_value = nil
      promise = Promise.new
      promise.resolve("Resolved Early")
      promise.then(->(v) { final_value = v })
      expect(final_value).to eq("Resolved Early")
    end

    it "should chain promises with promise-returning handlers" do
      final_value = nil
      promise = Promise.new
      second_promise = Promise.new

      promise
        .then(->(_) { second_promise })
        .then(->(v) { final_value = v })

      promise.resolve("Start")
      second_promise.resolve("Chained")
      expect(final_value).to eq("Chained")
    end
  end

  context "Promise Rejection" do
    it "should reject with an error" do
      rejected_reason = nil
      promise = Promise.new
      promise.catch(->(e) { rejected_reason = e })
      promise.reject("Rejection Reason")
      expect(rejected_reason).to eq("Rejection Reason")
    end

    it "should propagate rejection through the chain" do
      rejected_reason = nil
      promise = Promise.new
      promise
        .then(->(v) { "#{v} World" })
        .then(nil, ->(e) { rejected_reason = e })
      promise.reject("Error occurred")
      expect(rejected_reason).to eq("Error occurred")
    end

    it "should catch and recover from rejection with catch" do
      final_value = nil
      promise = Promise.new
      promise
        .then(->(v) { raise StandardError.new("Error!") })
        .catch(->(e) { "Recovered" })
        .then(->(v) { final_value = v })
      promise.resolve("Start")
      expect(final_value).to eq("Recovered")
    end

    it "should propagate errors thrown in on_resolve to catch" do
      final_error = nil
      promise = Promise.new
      promise
        .then(->(_) { raise StandardError.new("Error in resolve!") })
        .catch(->(e) { final_error = e.message })
      promise.resolve("Start")
      expect(final_error).to eq("Error in resolve!")
    end
  end

  context "Mixed Resolved and Rejected" do
    it "should propagate correct values across then and catch" do
      final_value = nil
      promise = Promise.new
      promise
        .then(->(_) { raise StandardError.new("First Error") })
        .catch(->(e) { "#{e.message} caught!" })
        .then(->(v) { final_value = v })
      promise.resolve("Start")
      expect(final_value).to eq("First Error caught!")
    end

    it "should chain promise that returns a promise and resolve correctly" do
      final_value = nil
      promise = Promise.new
      second_promise = Promise.new

      promise
        .then(->(_) { second_promise })
        .then(->(v) { final_value = v })

      promise.resolve("First")
      second_promise.resolve("Second")
      expect(final_value).to eq("Second")
    end
  end

  context "Edge Cases" do
    it "should handle late .then calls after rejection" do
      rejected_reason = nil
      promise = Promise.new
      promise.reject("Immediate Rejection") rescue ""
      promise.then(nil, ->(e) { rejected_reason = e })
      expect(rejected_reason).to eq("Immediate Rejection")
    end

    it "should not allow resolution after rejection" do
      rejected_reason = nil
      resolved_value = nil
      promise = Promise.new
      promise.catch(->(e) { rejected_reason = e })
      promise.then(->(v) { resolved_value = v }, ->(v) { })
      promise.reject("First Rejection")
      promise.resolve("Attempt to resolve after rejection")
      expect(rejected_reason).to eq("First Rejection")
      expect(resolved_value).to be_nil
    end

    it "should not allow rejection after resolution" do
      resolved_value = nil
      rejected_reason = nil
      promise = Promise.new
      promise.then(->(v) { resolved_value = v })
      promise.catch(->(e) { rejected_reason = e })
      promise.resolve("First Resolution")
      promise.reject("Attempt to reject after resolution")
      expect(resolved_value).to eq("First Resolution")
      expect(rejected_reason).to be_nil
    end

    it "should raise error when there is no catch block to handle rejection" do
      expect {
        promise = Promise.new
        promise.reject("Unhandled Rejection")
      }.to raise_error("Unhandled Rejection")
    end

    it "should not raise error when rejection is caught in later promise" do
      promise = Promise.new
      expect {
        promise.then(->(_) { raise StandardError.new("Error!") })
          .catch(->(_) { })
          .then(->(v) { v })
        promise.resolve("Start")
      }.not_to raise_error
    end
  end
end
