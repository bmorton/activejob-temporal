# frozen_string_literal: true

require 'active_job'

class TestJob < ActiveJob::Base
  def perform(*_args)
    # no-op
  end
end

class QueuedJob < ActiveJob::Base
  queue_as :payments

  def perform(*_args)
    # no-op
  end
end

class PriorityJob < ActiveJob::Base
  queue_with_priority 10

  def perform(*_args)
    # no-op
  end
end
