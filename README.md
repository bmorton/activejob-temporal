# ActiveJob::Temporal

[![CI](https://github.com/bmorton/activejob-temporal/actions/workflows/ci.yml/badge.svg)](https://github.com/bmorton/activejob-temporal/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/activejob-temporal.svg)](https://rubygems.org/gems/activejob-temporal)

An [ActiveJob](https://guides.rubyonrails.org/active_job_basics.html) queue adapter backed by
[Temporal Standalone Activities](https://docs.temporal.io/activities/standalone-activities) —
durable, retryable background jobs with zero new infrastructure beyond a worker process.

> **Status:** pre-1.0. Temporal Standalone Activities are in Public Preview and the Ruby SDK
> surface is experimental; APIs may change before the stable release.

## Requirements

- Ruby 3.3+ (3.4 / 4.0 supported)
- Rails 7.2+
- Temporal Server 1.31.0+ / Temporal CLI 1.7.0+ (dev server has standalone activities enabled)
- `temporalio` gem 1.3+ (verified against 1.6.x)

## Installation

```ruby
# Gemfile
gem "activejob-temporal"
```

```console
$ rails g active_job:temporal:install
```

## Configuration

```ruby
# config/initializers/active_job_temporal.rb
ActiveJob::Temporal.configure do |config|
  config.address   = ENV.fetch("TEMPORAL_ADDRESS", "localhost:7233")
  config.namespace = ENV.fetch("TEMPORAL_NAMESPACE", "default")
  config.api_key   = ENV["TEMPORAL_API_KEY"] # Temporal Cloud
  config.tls       = true if ENV["TEMPORAL_API_KEY"].present?

  config.default_task_queue = "default"
  config.default_start_to_close_timeout = 3600

  # Temporal owns durable retries by default — do NOT also use retry_on
  # (double-retry hazard) unless you set retry_policy max_attempts to 1.
  config.default_retry_policy = Temporalio::RetryPolicy.new(
    max_attempts: 25, initial_interval: 1.0, backoff_coefficient: 2.0
  )

  config.graceful_shutdown_period = 30

  # Custom ActiveJob priority (higher = more important) → Temporal
  # priority_key (lower = higher) mapping. Default: 6 - clamped priority.
  config.priority_mapper = ->(aj_priority) { (100 - aj_priority).clamp(1, 5) }
end

Rails.application.config.active_job.queue_adapter = :temporal
```

If `config.address` is left unset, connection options are loaded from
`Temporalio::EnvConfig` (`TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, TLS env
vars, etc.) before falling back to `localhost:7233` / `default`.

## Running the worker

```console
$ bin/temporal-jobs -q default -q payments --concurrency 50 --graceful-timeout 60
```

`--graceful-timeout N` (seconds) bounds how long the worker waits for
in-flight activities to finish on shutdown; default 30.

or via rake: `bundle exec rake temporal_jobs:work QUEUES=default,payments`.

## Feature mapping

| ActiveJob | Temporal standalone activity |
|---|---|
| `queue_name` | Task queue (`task_queue:`) |
| `perform_later` | `client.start_activity(ExecutionActivity, job.serialize, ...)` |
| `wait` / `wait_until` | `start_delay:` (seconds; not applied to retry attempts) |
| `priority` | `Priority#priority_key` (clamped 1–5, lower = higher) |
| retries | `Temporalio::RetryPolicy` (Temporal owns retries by default) |
| `job_id` | Activity `id:` |
| `provider_job_id` | `ActivityHandle#id` |
| `perform_all_later` | Loop of `start_activity` with per-job `enqueue_error` |
| cancellation | `ActiveJob::Temporal.cancel(job_id)` / `.terminate(job_id)` |

## Per-job options

```ruby
class ChargeCardJob < ApplicationJob
  queue_as :payments

  temporal_options(
    start_to_close_timeout: 120,
    retry_policy: Temporalio::RetryPolicy.new(max_attempts: 5),
    non_retryable_error_types: %w[CardDeclined], # merged into retry policy
    priority: 1,                      # Temporal priority_key 1 (highest)
    fairness_key: ->(job) { job.arguments.first.to_s }, # fair dispatch per key
    fairness_weight: 1.0,             # weight within its fairness key
    id_conflict_policy: :use_existing # dedup while running
  )
  def perform(card_id) = ...
end
```

## Known limitations (Public Preview)

- Pause, reset, and update-options are not supported yet.
- `TerminateExisting` conflict policy / `TerminateIfRunning` reuse policy are not supported yet.
- `start_delay` is accepted by the dev server (1.31.x) but first dispatch is not yet deferred;
  verify timing behavior against your target Temporal version.
- Enqueue is fire-and-forget: job failures surface in Temporal visibility/metrics/Web UI,
  not synchronously.

## Forking servers (Puma, Pitchfork, Unicorn)

SDK objects cannot cross forks. The client connects lazily; reset it after fork:

```ruby
# config/puma.rb
on_worker_boot { ActiveJob::Temporal.reset_client! }
```

## License

MIT
