# frozen_string_literal: true

require 'active_job'
require 'active_support/notifications'

module ActiveJob
  module QueueAdapters
    # ActiveJob adapter backed by Temporal Standalone Activities.
    #
    #   Rails.application.config.active_job.queue_adapter = :temporal
    class TemporalAdapter < (defined?(AbstractAdapter) ? AbstractAdapter : Object)
      def initialize(config = ActiveJob::Temporal.config)
        super()
        @config = config
      end

      def enqueue(job)
        handle = client.start_activity(
          ActiveJob::Temporal::ExecutionActivity, job.serialize,
          **activity_options(job)
        )
        job.provider_job_id = handle.id
        instrument(job, handle)
        handle
      end

      def enqueue_at(job, timestamp)
        delay = timestamp - Time.now.to_f
        handle = client.start_activity(
          ActiveJob::Temporal::ExecutionActivity, job.serialize,
          start_delay: [delay, 0.0].max,
          **activity_options(job)
        )
        job.provider_job_id = handle.id
        instrument(job, handle)
        handle
      end

      def enqueue_all(jobs)
        jobs.each do |job|
          if job.scheduled_at
            enqueue_at(job, job.scheduled_at.to_f)
          else
            enqueue(job)
          end
          job.successfully_enqueued = true
        rescue StandardError => e
          job.successfully_enqueued = false
          job.enqueue_error = ActiveJob::EnqueueError.new(e.message)
        end
        jobs.count(&:successfully_enqueued?)
      end

      # Temporal is a separate datastore from the app DB; defer enqueue until
      # after the surrounding transaction commits (matches SolidQueue/Sidekiq).
      def enqueue_after_transaction_commit?
        true
      end

      def stopping?
        false
      end

      private

      def client
        @config.client_manager.client
      end

      def instrument(job, handle)
        ActiveSupport::Notifications.instrument(
          'enqueue.temporal.activejob',
          job: job, activity_id: handle.id, run_id: handle.run_id
        )
      end

      def activity_options(job)
        opts = ActiveJob::Temporal::JobOptions.resolve(job, @config)
        {
          id: job.job_id,
          task_queue: opts.task_queue,
          start_to_close_timeout: opts.start_to_close_timeout,
          schedule_to_close_timeout: opts.schedule_to_close_timeout,
          retry_policy: opts.retry_policy,
          priority: opts.priority,
          static_summary: job.class.name,
          id_conflict_policy: opts.id_conflict_policy,
          id_reuse_policy: opts.id_reuse_policy
        }.compact
      end
    end
  end
end
