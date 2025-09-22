require 'thread'
require 'logger'

class JobQueue
  @logger = Logger.new($stdout)
  @queue = Queue.new
  # tuned defaults for very small servers
  @max_size = (ENV['PHOTO_QUEUE_MAX'] || 20).to_i
  @workers = []
  # single worker by default to limit memory/CPU on small machines
  @worker_count = (ENV['PHOTO_WORKER_THREADS'] || 1).to_i

  class << self
    def start
      return if @started
      @started = true
      @worker_count.times do |i|
        @workers << Thread.new do
          Thread.current.name = "photo-worker-#{i}" rescue nil
          loop do
            task = @queue.pop
            begin
              task.call
            rescue => e
              @logger.error("JobQueue worker error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
            end
          end
        end
      end
      @logger.info("JobQueue started with #{@worker_count} threads")
    end

    def enqueue(&block)
      raise ArgumentError, 'block required' unless block_given?
      start
      if @queue.size >= @max_size
        @logger.warn("JobQueue full (#{@queue.size}). Dropping job.")
        return false
      end
      @queue << block
      true
    end

    def shutdown(timeout = 5)
      @workers.each { |t| t.kill }
      @workers.clear
      @started = false
    end
  end
end

# example replacement in handlers/message_handler.rb (where you currently call Thread.new)
JobQueue.enqueue do
  # same body as your current thread block (scan, OFF lookup, matching, send messages, Product.save_for_item)
end