# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveJob::Temporal::Worker do
  let(:config) { ActiveJob::Temporal.config }
  let(:client) { instance_double(Temporalio::Client) }

  before do
    allow(config.client_manager).to receive(:client).and_return(client)
    allow(Temporalio::Worker).to receive(:new).and_return(instance_double(Temporalio::Worker))
    allow(Temporalio::Worker).to receive(:run_all)
  end

  it 'builds one worker per queue with ExecutionActivity registered' do
    described_class.run(queues: %w[a b])

    expect(Temporalio::Worker).to have_received(:new).twice
    expect(Temporalio::Worker).to have_received(:new).with(
      hash_including(client: client, task_queue: 'a',
                     activities: [ActiveJob::Temporal::ExecutionActivity])
    )
    expect(Temporalio::Worker).to have_received(:new).with(
      hash_including(client: client, task_queue: 'b',
                     activities: [ActiveJob::Temporal::ExecutionActivity])
    )
  end

  it 'passes graceful_shutdown_period through and falls back to config default' do
    described_class.run(queues: ['a'], graceful_shutdown_period: 7)
    expect(Temporalio::Worker).to have_received(:new).with(hash_including(graceful_shutdown_period: 7))

    config.graceful_shutdown_period = 42
    described_class.run(queues: ['a'])
    expect(Temporalio::Worker).to have_received(:new).with(hash_including(graceful_shutdown_period: 42))
  end

  it 'runs all workers with default shutdown signals' do
    described_class.run(queues: ['a'])
    expect(Temporalio::Worker).to have_received(:run_all).with(anything, shutdown_signals: %w[SIGINT SIGTERM])
  end

  it 'uses a fixed tuner with the requested concurrency' do
    tuner = instance_double(Temporalio::Worker::Tuner)
    allow(Temporalio::Worker::Tuner).to receive(:create_fixed).and_return(tuner)

    described_class.run(queues: ['a'], concurrency: 5)

    expect(Temporalio::Worker::Tuner).to have_received(:create_fixed).with(activity_slots: 5)
    expect(Temporalio::Worker).to have_received(:new).with(hash_including(tuner: tuner))
  end
end
