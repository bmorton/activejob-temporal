# frozen_string_literal: true

require 'temporalio'
require 'temporalio/activity'
require 'active_job'

module ActiveJob
  module Temporal
    # The single generic dispatch activity. Registered once on every worker,
    # it re-instantiates the correct ActiveJob class and runs the full
    # ActiveJob lifecycle (callbacks, retry_on/discard_on, deserialization).
    class ExecutionActivity < Temporalio::Activity::Definition
      activity_name 'ActiveJobExecution'

      def execute(job_data)
        ::ActiveJob::Base.execute(job_data)
      end
    end
  end
end
