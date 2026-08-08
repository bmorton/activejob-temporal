# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial release: `queue_adapter = :temporal` mapping ActiveJob onto Temporal
  Standalone Activities via a single generic `ActiveJobExecution` dispatch activity.
- `Configuration` with env-based connection defaults and `temporal_options` per-job DSL.
- `ClientManager` (lazy, fork-safe) with `ActiveJob::Temporal.reset_client!`.
- `bin/temporal-jobs` CLI and `temporal_jobs:work` rake task with multi-queue support.
- `PriorityMapper` (ActiveJob priority → clamped Temporal `priority_key` 1–5).
- `enqueue_all` with per-job `successfully_enqueued` / `enqueue_error`.
- `ActiveJob::Temporal.cancel(job_id)` / `.terminate(job_id)` helpers.
- `ActiveSupport::Notifications` instrumentation (`enqueue.temporal.activejob`).
- Rails generator (`active_job:temporal:install`) and Railtie.
- Integration test suite against a real Temporal dev server via the Temporal CLI.

## [Unreleased]

### Added
- `--graceful-timeout` CLI flag (per-queue grace period on shutdown).
- Connection falls back to `Temporalio::EnvConfig` when `config.address` unset.
- TLS auto-enabled when an API key is configured.
- `temporal_options`: `non_retryable_error_types` (merged into retry policy),
  `fairness_key` / `fairness_weight`.
- `config.priority_mapper` for custom ActiveJob→Temporal priority mapping.
- Shared adapter conformance examples; GlobalID integration test.
- RBS signatures (`sig/active_job/temporal.rbs`).
- CI/release/CodeQL workflows, dependabot, Appraisals, CONTRIBUTING,
  CODE_OF_CONDUCT, SECURITY, .yardopts.
