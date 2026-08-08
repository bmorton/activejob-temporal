# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveJob::Temporal::JobOptions do
  let(:config) { ActiveJob::Temporal.config }

  def job_class(options = {})
    Class.new(ActiveJob::Base) do
      temporal_options(options) unless options.empty?
      def self.name = 'OptsJob'
      def perform; end
    end
  end

  describe '.normalize_option' do
    it 'maps id_conflict_policy symbols to enums' do
      expect(described_class.normalize_option(:id_conflict_policy, :fail))
        .to eq(Temporalio::ActivityIDConflictPolicy::FAIL)
      expect(described_class.normalize_option(:id_conflict_policy, :use_existing))
        .to eq(Temporalio::ActivityIDConflictPolicy::USE_EXISTING)
    end

    it 'maps id_reuse_policy symbols to enums' do
      expect(described_class.normalize_option(:id_reuse_policy, :reject_duplicate))
        .to eq(Temporalio::ActivityIDReusePolicy::REJECT_DUPLICATE)
    end

    it 'raises KeyError for an unknown policy symbol' do
      expect { described_class.normalize_option(:id_conflict_policy, :bogus) }
        .to raise_error(KeyError)
    end

    it 'passes through other option values unchanged' do
      expect(described_class.normalize_option(:start_to_close_timeout, 60)).to eq(60)
    end
  end

  describe '.resolve precedence' do
    it 'prefers job options over config defaults' do
      config.default_start_to_close_timeout = 300
      job = job_class(start_to_close_timeout: 60).new
      expect(described_class.resolve(job, config).start_to_close_timeout).to eq(60)
    end

    it 'falls back to config defaults when the job sets nothing' do
      config.default_start_to_close_timeout = 300
      job = job_class.new
      expect(described_class.resolve(job, config).start_to_close_timeout).to eq(300)
    end

    it 'resolves task_queue from the job queue_name' do
      klass = job_class
      klass.queue_as 'payments'
      expect(described_class.resolve(klass.new, config).task_queue).to eq('payments')
    end
  end

  describe '.resolve priority' do
    it 'returns nil when neither priority nor fairness is set' do
      job = job_class.new
      expect(described_class.resolve(job, config).priority).to be_nil
    end

    it 'maps ActiveJob priority through the default mapper' do
      job = job_class(priority: 3).new
      expect(described_class.resolve(job, config).priority.priority_key).to eq(3)
    end

    it 'honors a custom config.priority_mapper proc' do
      config.priority_mapper = ->(_p) { Temporalio::Priority.new(priority_key: 1) }
      job = job_class(priority: 5).new
      expect(described_class.resolve(job, config).priority.priority_key).to eq(1)
    end

    it 'builds a Priority with fairness fields when fairness is set' do
      job = job_class(fairness_key: 'tenant-1', fairness_weight: 2.0).new
      priority = described_class.resolve(job, config).priority
      expect(priority.fairness_key).to eq('tenant-1')
      expect(priority.fairness_weight).to eq(2.0)
    end
  end

  describe '.resolve_retry_policy' do
    it 'returns the policy unchanged without non_retryable_error_types' do
      policy = Temporalio::RetryPolicy.new(max_attempts: 3)
      job = job_class(retry_policy: policy).new
      expect(described_class.resolve(job, config).retry_policy).to equal(policy)
    end

    it 'merges non_retryable_error_types into a copy' do
      policy = Temporalio::RetryPolicy.new(max_attempts: 3)
      job = job_class(retry_policy: policy, non_retryable_error_types: %w[Fatal]).new
      resolved = described_class.resolve(job, config).retry_policy
      expect(resolved.non_retryable_error_types).to eq(%w[Fatal])
      expect(resolved.max_attempts).to eq(3)
      expect(policy.non_retryable_error_types).to be_nil # original untouched
    end
  end
end
