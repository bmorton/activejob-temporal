# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveJob::Temporal::ClientManager do
  let(:config) { ActiveJob::Temporal.config }
  subject(:manager) { described_class.new(config) }

  before do
    allow(Temporalio::Client).to receive(:connect).and_return(instance_double(Temporalio::Client))
  end

  it 'memoizes the client' do
    2.times { manager.client }
    expect(Temporalio::Client).to have_received(:connect).once
  end

  it 'reconnects after reset!' do
    manager.client
    manager.reset!
    manager.client
    expect(Temporalio::Client).to have_received(:connect).twice
  end

  it 'uses config address and namespace when set' do
    config.address = 'example:7233'
    config.namespace = 'myns'
    manager.client
    expect(Temporalio::Client).to have_received(:connect).with('example:7233', 'myns', anything)
  end

  context 'when address is unset (EnvConfig fallback)' do
    before do
      config.address = nil
      allow(Temporalio::EnvConfig::ClientConfig).to receive(:load_client_connect_options)
        .and_return([['env:7233', 'envns'], { tls: true }])
    end

    it 'falls back to EnvConfig address and namespace' do
      manager.client
      expect(Temporalio::Client).to have_received(:connect).with('env:7233', 'envns', anything)
    end

    it 'lets explicit config values win over EnvConfig options' do
      config.tls = false
      manager.client
      expect(Temporalio::Client).to have_received(:connect)
        .with(anything, anything, hash_including(tls: false))
    end
  end

  it 'auto-enables TLS when an api_key is configured' do
    fresh = ActiveJob::Temporal::Configuration.new
    fresh.address = 'x:1'
    described_class.new(fresh).client
    expect(Temporalio::Client).to have_received(:connect)
      .with(anything, anything, hash_excluding(:tls))

    with_api_key = ActiveJob::Temporal::Configuration.new
    with_api_key.address = 'x:1'
    # api_key present at initialize → tls defaults true
    with_api_key.instance_variable_set(:@api_key, 'k')
    with_api_key.instance_variable_set(:@tls, true)
    described_class.new(with_api_key).client
    expect(Temporalio::Client).to have_received(:connect)
      .with(anything, anything, hash_including(tls: true))
  end

  it 'includes data_converter only when configured' do
    manager.client
    expect(Temporalio::Client).to have_received(:connect)
      .with(anything, anything, hash_excluding(:data_converter))

    converter = Object.new
    config.data_converter = converter
    described_class.new(config).client
    expect(Temporalio::Client).to have_received(:connect)
      .with(anything, anything, hash_including(data_converter: converter))
  end
end
