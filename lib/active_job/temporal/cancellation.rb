# frozen_string_literal: true

module ActiveJob
  module Temporal
    module Cancellation
      module_function

      # Request cancellation of a running activity by ActiveJob job_id.
      def cancel(job_id, reason = nil, activity_run_id: nil)
        ActiveJob::Temporal.activity_handle(job_id, activity_run_id: activity_run_id).cancel(reason)
      end

      # Force-close an activity by ActiveJob job_id.
      def terminate(job_id, reason = nil, activity_run_id: nil)
        ActiveJob::Temporal.activity_handle(job_id, activity_run_id: activity_run_id).terminate(reason)
      end
    end
  end
end
