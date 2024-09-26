require "async"
require "async/task"
require "time"
require "./app/services/backend/base"
require "./lib/helpers/async_promise"


RSpec.describe StorageBackendSocket do
  describe "Class<StorageBackendSocket>" do
    it "should load correctly, and print out in the order of delay since execution" do
      puts ""
      puts "current running reactor is: #{Async::Task.current?}"
      expect(Async::Task.current?).to be_nil()
      sample_backend_socket = StorageBackendSocket.new()
      delta_time = delta_time = Time.now
      # It is necessary to wrap the whole thing in either an [Async] or [Sync] context block (aka a reactor) for it to run asynchronously.
      # Otherwise, at the top level, [Async] blocks WILL run synchronously, because each block will spawn its own new top-level Async context,
      # since they do not have a parental [Async] or [Sync] context block to register themselves as a child of.
      Sync do
        puts "current running reactor is: #{Async::Task.current?}"
        expect(Async::Task.current?).to be_truthy
        sample_backend_socket.is_ready = Async do
          sleep 0.5
          puts "0.5 seconds later: message 1, first promise"
          "hello world 1"
        end
        puts "0.0 seconds later: message 2, first promise not fulfilled yet, because its running state is still: #{sample_backend_socket.is_ready.running?}"
        promise2 = Async do
          sleep 0.25
          puts "0.25 seconds later: message 3, second concurrent promise"
          "hello world 2"
        end
        # sample_backend_socket.is_ready.wait # allows you to wait for a promise and get its value
        puts "0.5 seconds later: message 4, successfully waited for first promise, with value: #{sample_backend_socket.is_ready.wait}"
        puts "0.5 seconds later: message 5, successfully waited for second promise, with value: #{promise2.wait}"
        delta_time = Time.now - delta_time
        # the task runs for about 0.5 seconds, not any less, and not anything longer than 0.55 seconds.
        # a 0.75 seconds or longer execution time will mean that asynchronousity is not functioning correctly.
        expect(delta_time).to be_between(0.5, 0.6).inclusive
      end
      puts "Back to synchronous sequential execution."
    end

    it "should load correctly, and use AsyncPromise to print out in the order of delay since execution" do
      sample_backend_socket = StorageBackendSocket.new()
      delta_time = delta_time = Time.now
      Sync do
        sample_backend_socket.is_ready = AsyncPromise.new(->(_) {
          sleep 0.5
          puts "0.5 seconds later: message 1, first promise"
          "hello world 1"
        })
        promise2 = AsyncPromise.new(->(_) {
          sleep 0.25
          puts "0.25 seconds later: message 3, second concurrent promise"
          "hello world 2"
        })
        sample_backend_socket.is_ready.resolve(nil)
        promise2.resolve(nil)
        puts "0.0 seconds later: message 2, first promise not fulfilled yet, because its running state is still: #{sample_backend_socket.is_ready.status}"
        # sample_backend_socket.is_ready.wait # allows you to wait for a promise and get its value
        puts "0.5 seconds later: message 4, successfully waited for first promise, with value: #{sample_backend_socket.is_ready.wait}"
        puts "0.5 seconds later: message 5, successfully waited for second promise, with value: #{promise2.wait}"
        delta_time = Time.now - delta_time
        # the task runs for about 0.5 seconds, not any less, and not anything longer than 0.55 seconds.
        # a 0.75 seconds or longer execution time will mean that asynchronousity is not functioning correctly.
        expect(delta_time).to be_between(0.5, 0.6).inclusive
      end
      puts "Back to synchronous sequential execution."
    end
  end
end
