# frozen_string_literal: true

require 'active_job'

require_relative 'temporal/version'
require_relative 'temporal/errors'
require_relative 'temporal/priority_mapper'
require_relative 'temporal/configuration'
require_relative 'temporal/client_manager'
require_relative 'temporal/job_options'
require_relative 'temporal/execution_activity'
require_relative 'temporal/worker'
require_relative 'temporal/cancellation'
require_relative 'temporal/railtie' if defined?(Rails::Railtie)
require_relative 'queue_adapters/temporal_adapter'

module ActiveJob
  module Temporal
    class << self
      def configure
        yield config
        config
      end

      def config
        @config ||= Configuration.new
      end

      def reset_configuration!
        @config = Configuration.new
      end

      def reset_client!
        config.client_manager.reset!
      end

      # Get a handle for a running/executed activity by its ActiveJob job_id.
      def activity_handle(job_id, activity_run_id: nil)
        config.client_manager.client.activity_handle(job_id, activity_run_id: activity_run_id)
      end

      def cancel(job_id, reason = nil, activity_run_id: nil)
        Cancellation.cancel(job_id, reason, activity_run_id: activity_run_id)
      end

      def terminate(job_id, reason = nil, activity_run_id: nil)
        Cancellation.terminate(job_id, reason, activity_run_id: activity_run_id)
      end

      def verify_sdk_capabilities!
        return if ::Temporalio::Client.method_defined?(:start_activity)

        raise Error,
              "The installed temporalio gem (#{::Temporalio::VERSION}) does not support " \
              'Standalone Activities (Client#start_activity). Please upgrade temporalio.'
      end
    end

    verify_sdk_capabilities!
  end
end

ActiveJob::Base.extend(ActiveJob::Temporal::JobOptions::ClassMethods)
