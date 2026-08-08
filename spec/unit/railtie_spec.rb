# frozen_string_literal: true

require 'spec_helper'
require 'rails/railtie'
require 'active_job/temporal/railtie'
require 'rake'

RSpec.describe ActiveJob::Temporal::Railtie do
  it 'registers the :temporal queue adapter' do
    expect(ActiveJob::QueueAdapters.lookup(:temporal).name)
      .to eq('ActiveJob::QueueAdapters::TemporalAdapter')
  end

  describe 'rake task temporal_jobs:work' do
    before do
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      allow(ActiveJob::Temporal::Worker).to receive(:run)

      harness = Object.new.extend(Rake::DSL)
      described_class.rake_tasks.each { |block| harness.instance_exec(&block) }
    end

    it 'splits QUEUES env and runs the worker' do
      ENV['QUEUES'] = 'a, b'
      Rake::Task['temporal_jobs:work'].invoke
      expect(ActiveJob::Temporal::Worker).to have_received(:run)
        .with(hash_including(queues: %w[a b]))
    ensure
      ENV.delete('QUEUES')
    end

    it 'falls back to the default task queue' do
      Rake::Task['temporal_jobs:work'].invoke
      expect(ActiveJob::Temporal::Worker).to have_received(:run)
        .with(hash_including(queues: ['default']))
    end

    it 'passes CONCURRENCY env through as an integer' do
      ENV['CONCURRENCY'] = '9'
      Rake::Task['temporal_jobs:work'].invoke
      expect(ActiveJob::Temporal::Worker).to have_received(:run)
        .with(hash_including(concurrency: 9))
    ensure
      ENV.delete('CONCURRENCY')
    end
  end
end
