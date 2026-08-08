# frozen_string_literal: true

require 'tempfile'

require 'active_job/temporal/cli'

RSpec.describe ActiveJob::Temporal::CLI do
  it 'parses --graceful-timeout and passes it to Worker.run' do
    cli = described_class.new(['-q', 'alpha', '--graceful-timeout', '45'])
    allow(cli).to receive(:load_rails_app)
    allow(ActiveJob::Temporal::Worker).to receive(:run)

    cli.run

    expect(ActiveJob::Temporal::Worker).to have_received(:run).with(
      queues: ['alpha'], concurrency: nil, graceful_shutdown_period: 45
    )
  end

  it 'defaults graceful timeout to nil' do
    cli = described_class.new(['-q', 'alpha'])
    allow(cli).to receive(:load_rails_app)
    allow(ActiveJob::Temporal::Worker).to receive(:run)

    cli.run

    expect(ActiveJob::Temporal::Worker).to have_received(:run).with(
      queues: ['alpha'], concurrency: nil, graceful_shutdown_period: nil
    )
  end

  it 'collects repeated -q flags in order' do
    cli = described_class.new(%w[-q a -q b -r /dev/null])
    allow(cli).to receive(:load_rails_app)
    allow(ActiveJob::Temporal::Worker).to receive(:run)

    cli.run

    expect(ActiveJob::Temporal::Worker).to have_received(:run)
      .with(hash_including(queues: %w[a b]))
  end

  it 'passes concurrency and graceful-timeout through' do
    cli = described_class.new(%w[-q a -c 7 --graceful-timeout 45 -r /dev/null])
    allow(cli).to receive(:load_rails_app)
    allow(ActiveJob::Temporal::Worker).to receive(:run)

    cli.run

    expect(ActiveJob::Temporal::Worker).to have_received(:run)
      .with(hash_including(concurrency: 7, graceful_shutdown_period: 45))
  end

  it 'falls back to the default task queue when no -q given' do
    cli = described_class.new(%w[-r /dev/null])
    allow(cli).to receive(:load_rails_app)
    allow(ActiveJob::Temporal::Worker).to receive(:run)

    cli.run

    expect(ActiveJob::Temporal::Worker).to have_received(:run)
      .with(hash_including(queues: ['default']))
  end

  it 'loads the app from --require path' do
    Tempfile.create(['app', '.rb']) do |f|
      f.write("CLI_LOADED_MARKER = true\n")
      f.flush
      allow(ActiveJob::Temporal::Worker).to receive(:run)

      described_class.start(['-q', 'a', '-r', f.path])

      expect(defined?(CLI_LOADED_MARKER)).to be_truthy
    end
  ensure
    Object.send(:remove_const, :CLI_LOADED_MARKER) if defined?(CLI_LOADED_MARKER)
  end
end
