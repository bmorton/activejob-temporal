# frozen_string_literal: true

require 'optparse'
require 'active_job/temporal'

module ActiveJob
  module Temporal
    # bin/temporal-jobs entrypoint.
    class CLI
      def self.start(argv)
        new(argv).run
      end

      def initialize(argv)
        @argv = argv
        @queues = []
        @concurrency = nil
        @graceful_timeout = nil
      end

      def run
        parser.parse!(@argv)
        load_rails_app

        @queues = [ActiveJob::Temporal.config.default_task_queue] if @queues.empty?
        ActiveJob::Temporal::Worker.run(
          queues: @queues, concurrency: @concurrency,
          graceful_shutdown_period: @graceful_timeout
        )
      end

      private

      def parser
        OptionParser.new do |opts|
          opts.banner = 'Usage: temporal-jobs [options]'

          opts.on('-q', '--queue QUEUE', 'Task queue to poll (repeatable)') do |q|
            @queues << q
          end

          opts.on('-c', '--concurrency N', Integer, 'Max concurrent activity executions') do |n|
            @concurrency = n
          end

          opts.on('--graceful-timeout N', Integer, 'Worker drain window in seconds on shutdown') do |n|
            @graceful_timeout = n
          end

          opts.on('-r', '--require PATH', 'Path to app environment (default: config/environment.rb)') do |path|
            @require_path = path
          end
        end
      end

      def load_rails_app
        path = @require_path ||
               (File.exist?('config/environment.rb') ? './config/environment' : nil)
        return unless path

        require File.expand_path(path)
      end
    end
  end
end
