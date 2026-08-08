# frozen_string_literal: true

require 'logger'
require 'temporalio'
require 'temporalio/client'
require 'temporalio/retry_policy'

module ActiveJob
  module Temporal
    class Configuration
      attr_writer :logger

      attr_accessor :address, :namespace, :api_key, :tls,
                    :default_task_queue, :default_start_to_close_timeout,
                    :default_schedule_to_close_timeout, :default_retry_policy,
                    :graceful_shutdown_period, :data_converter, :interceptors,
                    :priority_mapper

      def initialize
        @address = ENV.fetch('TEMPORAL_ADDRESS', 'localhost:7233')
        @namespace = ENV.fetch('TEMPORAL_NAMESPACE', 'default')
        @api_key = ENV.fetch('TEMPORAL_API_KEY', nil)
        # Cloud API-key auth implies TLS unless explicitly overridden.
        @tls = @api_key ? true : nil
        @default_task_queue = 'default'
        @default_start_to_close_timeout = 3600
        @default_schedule_to_close_timeout = nil
        @default_retry_policy = Temporalio::RetryPolicy.new(
          max_attempts: 25, initial_interval: 1.0, backoff_coefficient: 2.0
        )
        @graceful_shutdown_period = 30
        @data_converter = nil
        @interceptors = []
        @logger = nil
      end

      def client_manager
        @client_manager ||= ClientManager.new(self)
      end

      def logger
        @logger || (defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger) ||
          Logger.new($stdout, level: Logger::WARN)
      end
    end
  end
end
