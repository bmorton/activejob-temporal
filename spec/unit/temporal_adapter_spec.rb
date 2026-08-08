# frozen_string_literal: true

require 'active_job/queue_adapters/temporal_adapter'

RSpec.describe ActiveJob::QueueAdapters::TemporalAdapter do
  let(:handle) do
    instance_double(Temporalio::Client::ActivityHandle, id: 'test-id', run_id: 'run-id')
  end
  let(:client) do
    instance_double(Temporalio::Client).tap do |c|
      allow(c).to receive(:start_activity).and_return(handle)
    end
  end
  let(:manager) { instance_double(ActiveJob::Temporal::ClientManager, client: client) }
  let(:config) do
    ActiveJob::Temporal::Configuration.new.tap do |c|
      allow(c).to receive(:client_manager).and_return(manager)
    end
  end
  let(:adapter) { described_class.new(config) }

  describe '#enqueue' do
    it 'starts an activity with the job id, queue name and serialized job' do
      job = QueuedJob.new('hello')
      job.serialize
      adapter.enqueue(job)

      expect(client).to have_received(:start_activity).with(
        ActiveJob::Temporal::ExecutionActivity,
        hash_including('job_class' => 'QueuedJob'),
        hash_including(id: job.job_id, task_queue: 'payments', static_summary: 'QueuedJob')
      )
    end

    it 'falls back to the default task queue' do
      job = TestJob.new
      adapter.enqueue(job)

      expect(client).to have_received(:start_activity).with(
        anything, anything, hash_including(task_queue: 'default')
      )
    end

    it 'sets provider_job_id from the handle' do
      job = TestJob.new
      adapter.enqueue(job)

      expect(job.provider_job_id).to eq('test-id')
    end

    it 'includes a default start_to_close_timeout' do
      job = TestJob.new
      adapter.enqueue(job)

      expect(client).to have_received(:start_activity).with(
        anything, anything, hash_including(start_to_close_timeout: 3600)
      )
    end

    it 'includes a default retry policy' do
      job = TestJob.new
      adapter.enqueue(job)

      expect(client).to have_received(:start_activity).with(
        anything, anything, hash_including(retry_policy: an_instance_of(Temporalio::RetryPolicy))
      )
    end
  end

  describe '#enqueue_at' do
    it 'passes a positive start_delay in seconds' do
      job = TestJob.new
      adapter.enqueue_at(job, Time.now.to_f + 60)

      expect(client).to have_received(:start_activity).with(
        anything, anything, hash_including(start_delay: be_within(2).of(60.0))
      )
    end

    it 'floors negative delays at zero' do
      job = TestJob.new
      adapter.enqueue_at(job, Time.now.to_f - 60)

      expect(client).to have_received(:start_activity).with(
        anything, anything, hash_including(start_delay: 0.0)
      )
    end

    it 'sets provider_job_id' do
      job = TestJob.new
      adapter.enqueue_at(job, Time.now.to_f + 5)

      expect(job.provider_job_id).to eq('test-id')
    end
  end

  describe '#enqueue_all' do
    it 'enqueues every job and marks them successfully enqueued' do
      jobs = [TestJob.new, TestJob.new]
      count = adapter.enqueue_all(jobs)

      expect(count).to eq(2)
      expect(jobs).to all(be_successfully_enqueued)
      expect(client).to have_received(:start_activity).twice
    end

    it 'records enqueue_error for failures and continues' do
      call = 0
      allow(client).to receive(:start_activity) do
        call += 1
        raise 'boom' if call == 1

        handle
      end

      jobs = [TestJob.new, TestJob.new]
      count = adapter.enqueue_all(jobs)

      expect(count).to eq(1)
      expect(jobs[0]).not_to be_successfully_enqueued
      expect(jobs[0].enqueue_error).to be_a(ActiveJob::EnqueueError)
      expect(jobs[1]).to be_successfully_enqueued
    end

    it 'uses enqueue_at for scheduled jobs' do
      job = TestJob.new
      job.scheduled_at = Time.now + 30
      adapter.enqueue_all([job])

      expect(client).to have_received(:start_activity).with(
        anything, anything, hash_including(:start_delay)
      )
    end
  end

  describe '#enqueue_after_transaction_commit?' do
    it 'is true' do
      expect(adapter.enqueue_after_transaction_commit?).to be(true)
    end
  end

  describe '#stopping?' do
    it 'is false' do
      expect(adapter.stopping?).to be(false)
    end
  end

  describe 'priority mapping' do
    it 'passes a clamped priority_key' do
      job = PriorityJob.new
      adapter.enqueue(job)

      expect(client).to have_received(:start_activity).with(
        anything, anything,
        hash_including(priority: Temporalio::Priority.new(priority_key: 5))
      )
    end

    it 'omits priority when job has none' do
      job = TestJob.new
      adapter.enqueue(job)

      opts = nil
      expect(client).to have_received(:start_activity) do |_act, _data, o|
        opts = o
      end
      expect(opts).not_to have_key(:priority)
    end
  end

  describe 'temporal_options DSL' do
    it 'flows per-job options through to start_activity' do
      stub_const('OptionsJob', Class.new(ActiveJob::Base) do
        temporal_options(start_to_close_timeout: 120, priority: 1, id_conflict_policy: :use_existing)

        def self.name
          'OptionsJob'
        end

        def perform
          nil
        end
      end)

      job = OptionsJob.new
      adapter.enqueue(job)

      expect(client).to have_received(:start_activity).with(
        anything, anything,
        hash_including(
          start_to_close_timeout: 120,
          priority: Temporalio::Priority.new(priority_key: 1),
          id_conflict_policy: Temporalio::ActivityIDConflictPolicy::USE_EXISTING
        )
      )
    end
  end

  describe 'instrumentation' do
    it 'emits enqueue.temporal.activejob' do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe('enqueue.temporal.activejob') do |*args|
        events << args.last
      end

      job = TestJob.new
      adapter.enqueue(job)

      expect(events.size).to eq(1)
      expect(events.last[:job]).to eq(job)
      expect(events.last[:activity_id]).to eq('test-id')
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end
end

RSpec.describe ActiveJob::QueueAdapters::TemporalAdapter, 'conformance' do
  let(:handle) do
    instance_double(Temporalio::Client::ActivityHandle, id: 'conf-id', run_id: 'run-id')
  end
  let(:client) do
    instance_double(Temporalio::Client).tap do |c|
      allow(c).to receive(:start_activity).and_return(handle)
    end
  end
  let(:manager) { instance_double(ActiveJob::Temporal::ClientManager, client: client) }
  let(:config) do
    ActiveJob::Temporal::Configuration.new.tap do |c|
      allow(c).to receive(:client_manager).and_return(manager)
    end
  end
  let(:adapter) { described_class.new(config) }

  include_examples 'an ActiveJob::Temporal conforming adapter'
end
