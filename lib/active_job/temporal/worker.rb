# frozen_string_literal: true

require 'temporalio'
require 'temporalio/worker'

module ActiveJob
  module Temporal
    # Builds and runs Temporal workers that poll ActiveJob-mapped task queues
    # and execute jobs through ExecutionActivity.
    class Worker
      def self.run(queues:, concurrency: nil, graceful_shutdown_period: nil, config: ActiveJob::Temporal.config)
        client = config.client_manager.client
        tuner = if concurrency
                  Temporalio::Worker::Tuner.create_fixed(activity_slots: concurrency)
                else
                  Temporalio::Worker::Tuner.create_fixed
                end
        drain = graceful_shutdown_period || config.graceful_shutdown_period

        workers = queues.map do |queue|
          Temporalio::Worker.new(
            client: client,
            task_queue: queue,
            activities: [ExecutionActivity],
            tuner: tuner,
            graceful_shutdown_period: drain
          )
        end

        Temporalio::Worker.run_all(*workers, shutdown_signals: %w[SIGINT SIGTERM])
      end
    end
  end
end
