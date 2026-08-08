# frozen_string_literal: true

RSpec.describe ActiveJob::Temporal::PriorityMapper do
  describe '.map' do
    it 'returns nil for nil' do
      expect(described_class.map(nil)).to be_nil
    end

    it 'clamps values above the max to the max' do
      expect(described_class.map(100)).to eq(Temporalio::Priority.new(priority_key: 5))
    end

    it 'clamps values below 1 to 1' do
      expect(described_class.map(0)).to eq(Temporalio::Priority.new(priority_key: 1))
      expect(described_class.map(-3)).to eq(Temporalio::Priority.new(priority_key: 1))
    end

    it 'passes through in-range values' do
      expect(described_class.map(2)).to eq(Temporalio::Priority.new(priority_key: 2))
    end

    it 'accepts an existing Temporalio::Priority' do
      priority = Temporalio::Priority.new(priority_key: 2, fairness_key: 'tenant-a')
      expect(described_class.map(priority)).to equal(priority)
    end

    it 'respects a custom server max' do
      expect(described_class.map(8, max: 8)).to eq(Temporalio::Priority.new(priority_key: 8))
    end
  end
end

RSpec.describe 'fairness options' do
  it 'temporal_options accepts fairness_key and fairness_weight' do
    stub_const('FairJob', Class.new(ActiveJob::Base) do
      temporal_options(priority: 2, fairness_key: 'tenant-a', fairness_weight: 2.5)

      def self.name = 'FairJob'
      def perform = nil
    end)

    opts = ActiveJob::Temporal::JobOptions.resolve(FairJob.new, ActiveJob::Temporal.config)
    expect(opts.priority).to eq(
      Temporalio::Priority.new(priority_key: 2, fairness_key: 'tenant-a', fairness_weight: 2.5)
    )
  end
end

RSpec.describe 'custom priority mapper' do
  it 'uses config.priority_mapper when set' do
    config = ActiveJob::Temporal.config
    config.priority_mapper = ->(v) { Temporalio::Priority.new(priority_key: 1) if v }

    opts = ActiveJob::Temporal::JobOptions.resolve(PriorityJob.new, config)
    expect(opts.priority).to eq(Temporalio::Priority.new(priority_key: 1))
  end
end
