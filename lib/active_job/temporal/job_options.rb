# frozen_string_literal: true

require 'temporalio'
require 'temporalio/activity'
require 'temporalio/error'
require 'temporalio/retry_policy'

module ActiveJob
  module Temporal
    # Per-job-class DSL: temporal_options(start_to_close_timeout: ..., ...)
    # Merged over Configuration defaults at enqueue time by JobOptions.resolve.
    module JobOptions
      Options = Struct.new(
        :start_to_close_timeout, :schedule_to_close_timeout,
        :retry_policy, :priority, :id_conflict_policy, :id_reuse_policy,
        :task_queue,
        keyword_init: true
      )

      CONFLICT_POLICIES = {
        fail: -> { Temporalio::ActivityIDConflictPolicy::FAIL },
        use_existing: -> { Temporalio::ActivityIDConflictPolicy::USE_EXISTING }
      }.freeze

      REUSE_POLICIES = {
        allow_duplicate: -> { Temporalio::ActivityIDReusePolicy::ALLOW_DUPLICATE },
        allow_duplicate_failed_only: -> { Temporalio::ActivityIDReusePolicy::ALLOW_DUPLICATE_FAILED_ONLY },
        reject_duplicate: -> { Temporalio::ActivityIDReusePolicy::REJECT_DUPLICATE }
      }.freeze

      module ClassMethods
        def self.extended(base)
          return if base.respond_to?(:temporal_job_options)

          base.class_attribute :temporal_job_options, instance_accessor: false
        end

        def temporal_options(options = nil, **kwargs)
          options = (options || {}).merge(kwargs)
          resolved = options.each_with_object({}) do |(key, value), hash|
            hash[key.to_sym] = JobOptions.normalize_option(key.to_sym, value)
          end
          self.temporal_job_options = (temporal_job_options || {}).merge(resolved)
        end
      end

      def self.normalize_option(key, value)
        case key
        when :id_conflict_policy
          value.is_a?(Symbol) ? CONFLICT_POLICIES.fetch(value).call : value
        when :id_reuse_policy
          value.is_a?(Symbol) ? REUSE_POLICIES.fetch(value).call : value
        else
          # Integers for :priority are clamped by PriorityMapper at resolve time.
          value
        end
      end

      # Merge per-job options over configuration defaults.
      def self.resolve(job, config) # rubocop:disable Metrics
        raw = job.class.respond_to?(:temporal_job_options) ? (job.class.temporal_job_options || {}) : {}

        Options.new(
          start_to_close_timeout: raw.fetch(:start_to_close_timeout, config.default_start_to_close_timeout),
          schedule_to_close_timeout: raw[:schedule_to_close_timeout] || config.default_schedule_to_close_timeout,
          retry_policy: resolve_retry_policy(raw, config),
          priority: resolve_priority(raw, job, config),
          id_conflict_policy: raw[:id_conflict_policy],
          id_reuse_policy: raw[:id_reuse_policy],
          task_queue: raw[:task_queue] || job.queue_name&.presence || config.default_task_queue
        )
      end

      def self.resolve_priority(raw, job, config) # rubocop:disable Metrics
        priority_value = raw.key?(:priority) ? raw[:priority] : job.priority
        has_fairness = raw[:fairness_key] || raw[:fairness_weight]
        return nil if priority_value.nil? && !has_fairness

        if config.priority_mapper
          config.priority_mapper.call(priority_value)
        elsif has_fairness
          key = priority_value.is_a?(Integer) ? priority_value.clamp(1, PriorityMapper::DEFAULT_SERVER_MAX) : nil
          Temporalio::Priority.new(
            priority_key: key,
            fairness_key: raw[:fairness_key],
            fairness_weight: raw[:fairness_weight]
          )
        else
          PriorityMapper.map(priority_value)
        end
      end

      def self.resolve_retry_policy(raw, config)
        policy = raw.fetch(:retry_policy, config.default_retry_policy)
        types = raw[:non_retryable_error_types]
        return policy if types.nil? || types.empty? || !policy

        Temporalio::RetryPolicy.new(
          initial_interval: policy.initial_interval,
          backoff_coefficient: policy.backoff_coefficient,
          max_interval: policy.max_interval,
          max_attempts: policy.max_attempts,
          non_retryable_error_types: (policy.non_retryable_error_types || []) + types
        )
      end
    end
  end
end
