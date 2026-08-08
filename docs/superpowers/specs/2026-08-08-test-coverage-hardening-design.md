# Test Coverage Hardening — Design

Date: 2026-08-08
Status: Approved by user 2026-08-08

## Goal

Make coverage measurable and close known test gaps so future contributors get
immediate signal when they break untested behavior.

## 1. Tooling: SimpleCov

- Add `simplecov` as a development dependency in the gemspec.
- Start SimpleCov at the very top of `spec/spec_helper.rb`, **before** any
  project requires, with:
  - `track_files 'lib/**/*.rb'`
  - groups: `Adapter` (`lib/active_job/queue_adapters`), `Core`
    (`lib/active_job/temporal`), `Generators` (`lib/generators`)
- `SimpleCov.minimum_coverage 95` — fails the suite if coverage drops below
  95% line coverage. Chosen high because the codebase is small and mostly thin
  wrappers; adjustable if integration-only paths prove impractical to cover.
- HTML report written to `coverage/` (added to `.gitignore`); CI prints the
  console summary only (no artifact upload — keep CI simple).
- Integration tests spawn worker **threads** in-process, not forked
  subprocesses, so SimpleCov's at-exit hook is unaffected. The one exception is
  any test shelling out to `exe/temporal-jobs`; that subprocess's coverage is
  not collected and its exercised lines are covered by unit specs instead.

## 2. New/expanded unit specs

### `spec/unit/worker_spec.rb` (new)
- `Worker.run` constructs one `Temporalio::Worker` per queue with
  `ExecutionActivity` registered.
- `graceful_shutdown_period` is passed through to `Worker.run_all`.
- `shutdown_signals` defaults applied. Mock `Temporalio::Worker` and
  `Temporalio::Worker.run_all`; no real server.

### `spec/unit/railtie_spec.rb` (new)
- `:temporal` queue adapter is registered with ActiveJob.
- Rake task `temporal_jobs:work` exists and reads `QUEUES` env var.
- Use a minimal fake `Rails::Railtie`/app harness; guard with
  `defined?(Rails)` skip if harness proves fragile — prefer heredoc-loaded
  railtie against a stub `Rails` module.

### `spec/unit/cli_spec.rb` (expand from 2 examples)
- `-q` repeatable queue parsing; `--concurrency`; `--graceful-timeout`
  passthrough to `Worker.run`.
- `--require` with a missing environment file exits non-zero with a clear
  message.
- Help output lists all flags.

### `spec/unit/client_manager_spec.rb` (new)
- `client` memoizes; `reset!` forces a reconnect.
- `connect` merges config over EnvConfig (config non-nil wins) when
  `config.address` is nil.
- TLS auto-enables when `api_key` present and `tls` unset.
- `data_converter` only included when configured. Mock `Temporalio::Client.connect`.

### `spec/unit/job_options_spec.rb` (new)
- `normalize_option` accepts symbol keys and validates option names against the
  known set; unknown option raises a clear error.
- `CONFLICT_POLICIES` / `REUSE_POLICIES` symbol→enum mapping, invalid symbol error.
- `resolve` precedence: job option → config default → library default.
- `resolve_priority` honors `config.priority_mapper` proc; `resolve_retry_policy`
  merges `non_retryable_error_types` without mutating the base policy.

### `spec/unit/execution_activity_spec.rb` (new)
- `execute(job_data)` delegates to `ActiveJob::Base.execute` with the payload
  unchanged (spy on `ActiveJob::Base`).
- Activity name remains `"ActiveJobExecution"` (public API stability guard).

## 3. New integration tests (`spec/integration/end_to_end_spec.rb`)

- **Duplicate enqueue with `:fail` conflict policy**: enqueue same job twice,
  second raises `Temporalio::Error::ActivityAlreadyStarted` (or SDK equivalent —
  assert the actual class discovered during implementation).
- **Terminate vs cancel**: terminate a pending activity; `handle.result` raises
  `ActivityFailedError`; `describe` shows terminated state.
- **Multi-queue worker**: one worker serving two queues performs jobs enqueued
  to either.

## Error handling

- SimpleCov must be the first require in `spec_helper.rb`; a comment warns
  against reordering.
- SimpleCov must not be required when running under a non-RSpec context
  (guard: only load when defined?(RSpec) is about to be true — implemented as
  unconditional load in spec_helper, which is RSpec-only).
- Minimum-coverage failure message must name uncovered files (SimpleCov
  default output does this).

## Testing the change itself

- `bundle exec rspec` green locally with dev server; `bundle exec rubocop` clean.
- CI matrix re-run green; console shows coverage summary ≥ 95%.

## Out of scope

- Mutation testing, branch coverage thresholds, Coveralls/Codecov services
  (console summary suffices for now).
