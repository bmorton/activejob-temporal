# frozen_string_literal: true

RSpec.describe ActiveJob::Temporal::Configuration do
  subject(:config) { described_class.new }

  it 'has sensible defaults' do
    expect(config.address).to eq('localhost:7233')
    expect(config.namespace).to eq('default')
    expect(config.default_task_queue).to eq('default')
    expect(config.default_start_to_close_timeout).to eq(3600)
    expect(config.default_retry_policy).to be_a(Temporalio::RetryPolicy)
    expect(config.graceful_shutdown_period).to eq(30)
  end

  it 'builds a lazy client manager' do
    expect(config.client_manager).to be_a(ActiveJob::Temporal::ClientManager)
    expect(config.client_manager).to equal(config.client_manager)
  end
end

RSpec.describe ActiveJob::Temporal::ClientManager do
  let(:config) { ActiveJob::Temporal::Configuration.new }
  subject(:manager) { described_class.new(config) }

  it 'memoizes the client' do
    fake = instance_double(Temporalio::Client)
    allow(Temporalio::Client).to receive(:connect).and_return(fake)

    expect(manager.client).to equal(manager.client)
    expect(Temporalio::Client).to have_received(:connect).once
  end

  it 'connects lazily' do
    allow(Temporalio::Client).to receive(:connect).and_return(instance_double(Temporalio::Client))
    manager.client
    expect(Temporalio::Client).to have_received(:connect).with(
      'localhost:7233', 'default', hash_including(lazy_connect: true)
    )
  end

  it 'resets the memoized client' do
    allow(Temporalio::Client).to receive(:connect).and_return(
      instance_double(Temporalio::Client), instance_double(Temporalio::Client)
    )
    first = manager.client
    manager.reset!
    expect(manager.client).not_to equal(first)
  end
end

RSpec.describe 'non-retryable error mapping' do
  it 'merges non_retryable_error_types into the resolved retry policy' do
    stub_const('DiscardJob', Class.new(ActiveJob::Base) do
      temporal_options(non_retryable_error_types: ['ActiveJob::DeserializationError'])

      def self.name = 'DiscardJob'
      def perform = nil
    end)

    opts = ActiveJob::Temporal::JobOptions.resolve(DiscardJob.new, ActiveJob::Temporal.config)
    expect(opts.retry_policy.non_retryable_error_types).to eq(['ActiveJob::DeserializationError'])
    expect(opts.retry_policy.max_attempts).to eq(25) # config default preserved
  end

  it 'keeps explicit retry_policy non_retryable types' do
    policy = Temporalio::RetryPolicy.new(max_attempts: 3, non_retryable_error_types: ['Foo'])
    stub_const('ExplicitJob', Class.new(ActiveJob::Base) do
      temporal_options(retry_policy: policy)

      def self.name = 'ExplicitJob'
      def perform = nil
    end)

    opts = ActiveJob::Temporal::JobOptions.resolve(ExplicitJob.new, ActiveJob::Temporal.config)
    expect(opts.retry_policy.non_retryable_error_types).to eq(['Foo'])
  end
end

RSpec.describe 'EnvConfig fallback' do
  it 'uses EnvConfig connect options when address is not explicitly set' do
    config = ActiveJob::Temporal::Configuration.new
    config.address = nil
    config.namespace = nil

    fake = instance_double(Temporalio::Client)
    allow(Temporalio::EnvConfig::ClientConfig).to receive(:load_client_connect_options)
      .and_return([['from-env:7233', 'envns'], { tls: true }])
    allow(Temporalio::Client).to receive(:connect).and_return(fake)

    expect(config.client_manager.client).to equal(fake)
    expect(Temporalio::Client).to have_received(:connect).with(
      'from-env:7233', 'envns', hash_including(tls: true, lazy_connect: true)
    )
  end
end
