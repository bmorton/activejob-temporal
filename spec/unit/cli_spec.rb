# frozen_string_literal: true

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
end
