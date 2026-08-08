# frozen_string_literal: true

# Full end-to-end integration test against a real Temporal dev server started
# via the Temporal CLI (`temporal server start-dev`).
RSpec.describe 'ActiveJob on Temporal end-to-end', :integration do
  before(:all) do
    ActiveJob::Temporal.reset_configuration!
    ActiveJob::Temporal.configure do |config|
      config.address = ENV.fetch('TEMPORAL_ADDRESS', 'localhost:7233')
      config.namespace = 'default'
      config.default_start_to_close_timeout = 30
      config.graceful_shutdown_period = 5
    end
  end

  def with_worker(queues:)
    config = ActiveJob::Temporal.config
    client = config.client_manager.client
    cancellation, cancel_proc = Temporalio::Cancellation.new

    workers = queues.map do |queue|
      Temporalio::Worker.new(
        client: client,
        task_queue: queue,
        activities: [ActiveJob::Temporal::ExecutionActivity],
        graceful_shutdown_period: 2
      )
    end

    thread = Thread.new do
      Temporalio::Worker.run_all(*workers, cancellation: cancellation, shutdown_signals: [])
    rescue StandardError
      # expected on shutdown
    end

    yield client
  ensure
    cancel_proc&.call
    thread&.join(15)
  end

  it 'performs an enqueued job on a real Temporal server' do
    performed = Queue.new

    stub_const('IntegrationJob', Class.new(ActiveJob::Base) do
      queue_as 'integration'

      define_method(:perform) do |value|
        performed << value
      end

      def self.name
        'IntegrationJob'
      end
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = IntegrationJob.new('hello-temporal')

    with_worker(queues: ['integration']) do
      adapter.enqueue(job)
      expect(job.provider_job_id).to eq(job.job_id)

      result = Timeout.timeout(30) { performed.pop }
      expect(result).to eq('hello-temporal')
    end
  end

  it 'retries a failing job and eventually performs it' do
    attempts = Queue.new

    stub_const('RetryJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-retry'

      define_method(:perform) do
        attempts << true
        raise 'transient failure' if attempts.size < 2
      end

      def self.name
        'RetryJob'
      end
    end)

    ActiveJob::Temporal.configure do |config|
      config.default_retry_policy = Temporalio::RetryPolicy.new(
        max_attempts: 3, initial_interval: 0.1
      )
    end

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = RetryJob.new

    with_worker(queues: ['integration-retry']) do
      adapter.enqueue(job)
      Timeout.timeout(30) { attempts.pop }
      Timeout.timeout(30) { attempts.pop }
    end
  end

  it 'enqueues a scheduled job with start_delay and performs it' do
    # NOTE: the Public Preview dev server (1.31.x) accepts start_delay but does
    # not defer first dispatch; exact timing is asserted in unit specs via the
    # start_delay argument. Here we verify enqueue_at works end-to-end.
    performed = Queue.new

    stub_const('DelayedJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-delay'

      define_method(:perform) do
        performed << Time.now.to_f
      end

      def self.name
        'DelayedJob'
      end
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = DelayedJob.new
    target = Time.now.to_f + 2

    with_worker(queues: ['integration-delay']) do
      adapter.enqueue_at(job, target)
      ran_at = Timeout.timeout(30) { performed.pop }
      expect(ran_at).to be <= target + 30 # performs successfully
    end
  end

  it 'cancels a pending delayed job' do
    performed = Queue.new

    stub_const('CancelJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-cancel'

      define_method(:perform) do
        performed << true
      end

      def self.name
        'CancelJob'
      end
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = CancelJob.new

    # No worker yet: the activity sits pending in the server regardless of
    # whether the server honors start_delay, so cancellation is deterministic.
    adapter.enqueue_at(job, Time.now.to_f + 60)
    ActiveJob::Temporal.cancel(job.job_id, 'no longer needed')

    handle = ActiveJob::Temporal.activity_handle(job.job_id)
    Timeout.timeout(30) { handle.result }
    raise 'expected cancellation to fail the result'
  rescue Temporalio::Error::ActivityFailedError => e
    expect(e.message).to match(/cancel|fail/i)
  end

  it 'exposes the execution via temporal CLI visibility', :cli do
    performed = Queue.new

    stub_const('VisibleJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-visible'

      define_method(:perform) do
        performed << true
      end

      def self.name
        'VisibleJob'
      end
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = VisibleJob.new

    with_worker(queues: ['integration-visible']) do
      adapter.enqueue(job)
      Timeout.timeout(30) { performed.pop }

      # Verify via the Ruby client
      handle = ActiveJob::Temporal.activity_handle(job.job_id)
      expect(handle.describe.raw_info.status).to eq(:ACTIVITY_EXECUTION_STATUS_COMPLETED)

      # Verify via the Temporal CLI (proof of visibility in Temporal tooling)
      output = `temporal activity describe --activity-id #{job.job_id} -n default --address localhost:7233 2>&1`
      expect($CHILD_STATUS.success?).to be(true), "temporal CLI failed: #{output}"
      expect(output).to include('Completed')
      expect(output).to include('integration-visible')
    end
  end
end

# Minimal GlobalID-identified model without ActiveRecord.
class FakeRecord
  include GlobalID::Identification

  attr_reader :id

  def initialize(id)
    @id = id
  end

  def self.find(id)
    new(id)
  end
end

RSpec.describe 'GlobalID round-trip', :integration do
  before(:all) do
    GlobalID.app = 'activejob-temporal-test'
    ActiveJob::Temporal.reset_configuration!
    ActiveJob::Temporal.configure do |config|
      config.address = ENV.fetch('TEMPORAL_ADDRESS', 'localhost:7233')
      config.default_start_to_close_timeout = 30
    end
  end

  it 'deserializes GlobalID arguments inside the worker' do
    received = Queue.new

    stub_const('GidJob', Class.new(ActiveJob::Base) do
      queue_as 'gid-integration'

      define_method(:perform) do |record|
        received << record.id
      end

      def self.name = 'GidJob'
    end)

    config = ActiveJob::Temporal.config
    client = config.client_manager.client
    cancellation, cancel = Temporalio::Cancellation.new
    worker = Temporalio::Worker.new(
      client: client, task_queue: 'gid-integration',
      activities: [ActiveJob::Temporal::ExecutionActivity],
      graceful_shutdown_period: 2
    )
    thread = Thread.new do
      Temporalio::Worker.run_all(worker, cancellation: cancellation, shutdown_signals: [])
    rescue StandardError
      nil
    end

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    adapter.enqueue(GidJob.new(FakeRecord.new('rec-42')))

    expect(Timeout.timeout(30) { received.pop }).to eq('rec-42')
  ensure
    cancel&.call
    thread&.join(15)
  end
end
