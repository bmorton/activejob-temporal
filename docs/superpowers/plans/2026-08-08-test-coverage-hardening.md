# Test Coverage Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SimpleCov with a 95% line-coverage floor and close all known test gaps (Worker, Railtie, CLI, ClientManager, JobOptions, ExecutionActivity unit specs + three new integration tests).

**Architecture:** Pure test/tooling change — no production code modified except `.gitignore` and gemspec dev dependencies. SimpleCov boots first in `spec_helper.rb` before any project requires. New unit specs mock SDK boundaries (`Temporalio::Client.connect`, `Temporalio::Worker`); new integration tests run against the real dev server.

**Tech Stack:** RSpec 3, SimpleCov, temporalio 1.6, ActiveJob 7.2–8.1.

**Spec:** `docs/superpowers/specs/2026-08-08-test-coverage-hardening-design.md`

## Global Constraints

- Ruby >= 3.3; ActiveJob/ActiveSupport >= 7.2, < 9.0; temporalio >= 1.3, < 2.0.
- RSpec: `verify_partial_doubles = true` is on — only stub methods that actually exist.
- Integration tests need the dev server: `temporal server start-dev --headless --port 7233` and CLI on `PATH`.
- RuboCop must stay clean; follow existing spec style (no monkey patching, `stub_const` for job classes).
- Verified SDK facts (do not re-derive): duplicate enqueue raises `Temporalio::Error::ActivityAlreadyStartedError`; `handle.describe.raw_info.status` returns a Symbol (e.g. `:ACTIVITY_EXECUTION_STATUS_COMPLETED`, `:ACTIVITY_EXECUTION_STATUS_TERMINATED`); terminated `handle.result` raises `Temporalio::Error::ActivityFailedError`.
- Commit message trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

---

### Task 1: SimpleCov tooling

**Files:**
- Modify: `activejob-temporal.gemspec` (add dev dependency)
- Modify: `spec/spec_helper.rb` (boot SimpleCov first)
- Modify: `.gitignore` (add `coverage/`)

**Interfaces:**
- Produces: SimpleCov active for all later tasks; `coverage/` dir gitignored. Console prints line coverage % and fails the suite below 95%.

- [ ] **Step 1: Add simplecov dev dependency**

In `activejob-temporal.gemspec`, after the existing `spec.add_dependency` lines:

```ruby
  spec.add_development_dependency 'simplecov', '~> 0.22'
```

- [ ] **Step 2: Install and verify load**

Run: `bundle install && bundle exec ruby -e "require 'simplecov'; puts SimpleCov::VERSION"`
Expected: prints `0.22.x`

- [ ] **Step 3: Boot SimpleCov in spec_helper (before ALL other requires)**

Replace the top of `spec/spec_helper.rb` (everything before `require 'rspec'`) with:

```ruby
# frozen_string_literal: true

# SimpleCov must be required before any project code so it can track loads.
require 'simplecov'
SimpleCov.start do
  track_files 'lib/**/*.rb'
  add_group 'Adapter', 'lib/active_job/queue_adapters'
  add_group 'Core', 'lib/active_job/temporal'
  add_group 'Generators', 'lib/generators'
end
SimpleCov.minimum_coverage 95

require 'rspec'
```

Keep the rest of spec_helper unchanged.

- [ ] **Step 4: Add coverage/ to .gitignore**

Append to `.gitignore`:

```
/coverage/
```

- [ ] **Step 5: Run suite — expect failure showing baseline coverage**

Run: `PATH="$PATH:/home/node/.temporalio/bin" bundle exec rspec`
Expected: 44 examples, 0 failures, but SimpleCov exits non-zero reporting coverage below the 95% minimum — this is the RED state proving the floor works.

- [ ] **Step 6: Commit**

```bash
git add activejob-temporal.gemspec Gemfile.lock spec/spec_helper.rb .gitignore
git commit -m "Add SimpleCov with 95% line coverage floor

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Worker unit spec

**Files:**
- Create: `spec/unit/worker_spec.rb`

**Interfaces:**
- Consumes: `ActiveJob::Temporal::Worker.run(queues:, concurrency: nil, graceful_shutdown_period: nil, config:)`; config default `graceful_shutdown_period` and `client_manager`.
- Produces: nothing new; locks current Worker wiring.

- [ ] **Step 1: Write the spec**

Create `spec/unit/worker_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveJob::Temporal::Worker do
  let(:config) { ActiveJob::Temporal.config }
  let(:client) { instance_double(Temporalio::Client) }

  before do
    allow(config.client_manager).to receive(:client).and_return(client)
    allow(Temporalio::Worker).to receive(:new).and_return(instance_double(Temporalio::Worker))
    allow(Temporalio::Worker).to receive(:run_all)
  end

  it 'builds one worker per queue with ExecutionActivity registered' do
    described_class.run(queues: %w[a b])

    expect(Temporalio::Worker).to have_received(:new).twice
    expect(Temporalio::Worker).to have_received(:new).with(
      hash_including(client: client, task_queue: 'a',
                     activities: [ActiveJob::Temporal::ExecutionActivity])
    )
    expect(Temporalio::Worker).to have_received(:new).with(
      hash_including(client: client, task_queue: 'b',
                     activities: [ActiveJob::Temporal::ExecutionActivity])
    )
  end

  it 'passes graceful_shutdown_period through and falls back to config default' do
    described_class.run(queues: ['a'], graceful_shutdown_period: 7)
    expect(Temporalio::Worker).to have_received(:new).with(hash_including(graceful_shutdown_period: 7))

    config.graceful_shutdown_period = 42
    described_class.run(queues: ['a'])
    expect(Temporalio::Worker).to have_received(:new).with(hash_including(graceful_shutdown_period: 42))
  end

  it 'runs all workers with default shutdown signals' do
    described_class.run(queues: ['a'])
    expect(Temporalio::Worker).to have_received(:run_all).with(anything, shutdown_signals: %w[SIGINT SIGTERM])
  end

  it 'uses a fixed tuner with the requested concurrency' do
    tuner = instance_double(Temporalio::Worker::Tuner)
    allow(Temporalio::Worker::Tuner).to receive(:create_fixed).and_return(tuner)

    described_class.run(queues: ['a'], concurrency: 5)

    expect(Temporalio::Worker::Tuner).to have_received(:create_fixed).with(activities: 5)
    expect(Temporalio::Worker).to have_received(:new).with(hash_including(tuner: tuner))
  end
end
```

- [ ] **Step 2: Run spec**

Run: `bundle exec rspec spec/unit/worker_spec.rb`
Expected: 4 examples, 0 failures. If the `run_all` matcher arity fails, adjust to match the actual call signature (`run_all(*workers, shutdown_signals:)`).

- [ ] **Step 3: Commit**

```bash
git add spec/unit/worker_spec.rb
git commit -m "Add Worker unit specs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: ClientManager unit spec

**Files:**
- Create: `spec/unit/client_manager_spec.rb`

**Interfaces:**
- Consumes: `ActiveJob::Temporal::ClientManager#client/#reset!`; private `connect` merges EnvConfig when `config.address` is nil; TLS auto-enable lives in `Configuration` (`@tls = @api_key ? true : nil`).
- Produces: locks memoization/reset and EnvConfig merge semantics.

- [ ] **Step 1: Write the spec**

Create `spec/unit/client_manager_spec.rb`:

```ruby
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
    fresh.api_key = 'secret'
    expect(fresh.tls).to be(true)
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
```

- [ ] **Step 2: Run spec**

Run: `bundle exec rspec spec/unit/client_manager_spec.rb`
Expected: 7 examples, 0 failures. If `hash_excluding` is unsupported, capture kwargs with a block and assert key absence.

- [ ] **Step 3: Commit**

```bash
git add spec/unit/client_manager_spec.rb
git commit -m "Add ClientManager unit specs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: JobOptions unit spec

**Files:**
- Create: `spec/unit/job_options_spec.rb`

**Interfaces:**
- Consumes: `JobOptions.normalize_option(key, value)`, `.resolve(job, config)`, `CONFLICT_POLICIES`, `REUSE_POLICIES`; job classes get `temporal_options` via the `ActiveJob::Base` extension.
- Produces: locks option validation, precedence, and merging rules.

- [ ] **Step 1: Write the spec**

Create `spec/unit/job_options_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run spec**

Run: `bundle exec rspec spec/unit/job_options_spec.rb`
Expected: 12 examples, 0 failures. Note: unknown *option keys* are currently stored silently — do NOT add new validation in this task; the spec only asserts KeyError for unknown *policy symbols* (existing behavior).

- [ ] **Step 3: Commit**

```bash
git add spec/unit/job_options_spec.rb
git commit -m "Add JobOptions unit specs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: ExecutionActivity unit spec

**Files:**
- Create: `spec/unit/execution_activity_spec.rb`

**Interfaces:**
- Consumes: `ExecutionActivity#execute(job_data)` → `ActiveJob::Base.execute(job_data)`; `activity_name 'ActiveJobExecution'`.
- Produces: public-API name guard.

- [ ] **Step 1: Write the spec**

Create `spec/unit/execution_activity_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveJob::Temporal::ExecutionActivity do
  it 'is registered under the stable public activity name' do
    expect(described_class._activity_definition.name).to eq('ActiveJobExecution')
  end

  it 'delegates execution to ActiveJob::Base.execute with the payload unchanged' do
    payload = { 'job_class' => 'SomeJob', 'arguments' => [1] }
    allow(ActiveJob::Base).to receive(:execute)

    described_class.new.execute(payload)

    expect(ActiveJob::Base).to have_received(:execute).with(payload)
  end
end
```

If `_activity_definition` is not the right introspection API, discover the correct one with `described_class.methods.grep(/activit/)` in a `bundle exec ruby -e` probe and adjust — the assertion target (name == `'ActiveJobExecution'`) must stay.

- [ ] **Step 2: Run spec**

Run: `bundle exec rspec spec/unit/execution_activity_spec.rb`
Expected: 2 examples, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add spec/unit/execution_activity_spec.rb
git commit -m "Add ExecutionActivity unit specs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: CLI spec expansion

**Files:**
- Modify: `spec/unit/cli_spec.rb`

**Interfaces:**
- Consumes: `CLI.start(argv)` → parse → `Worker.run(queues:, concurrency:, graceful_shutdown_period:)`; `-r/--require PATH` loads the app env; missing path falls back silently.

- [ ] **Step 1: Read existing cli_spec, then append examples**

Add `require 'tempfile'` at the top of `spec/unit/cli_spec.rb` if absent, then append inside the existing describe block:

```ruby
  before do
    allow(ActiveJob::Temporal::Worker).to receive(:run)
  end

  it 'collects repeated -q flags in order' do
    described_class.start(%w[-q a -q b -r /dev/null])
    expect(ActiveJob::Temporal::Worker).to have_received(:run)
      .with(hash_including(queues: %w[a b]))
  end

  it 'passes concurrency and graceful-timeout through' do
    described_class.start(%w[-q a -c 7 --graceful-timeout 45 -r /dev/null])
    expect(ActiveJob::Temporal::Worker).to have_received(:run)
      .with(hash_including(concurrency: 7, graceful_shutdown_period: 45))
  end

  it 'falls back to the default task queue when no -q given' do
    described_class.start(%w[-r /dev/null])
    expect(ActiveJob::Temporal::Worker).to have_received(:run)
      .with(hash_including(queues: ['default']))
  end

  it 'loads the app from --require path' do
    Tempfile.create(['app', '.rb']) do |f|
      f.write("$cli_loaded_marker = true\n")
      f.flush
      described_class.start(['-q', 'a', '-r', f.path])
      expect($cli_loaded_marker).to be(true)
    end
  ensure
    $cli_loaded_marker = nil
  end
```

- [ ] **Step 2: Run spec**

Run: `bundle exec rspec spec/unit/cli_spec.rb`
Expected: 2 existing + 4 new examples pass. If `-r /dev/null` errors, substitute a real tempfile for those examples too.

- [ ] **Step 3: Commit**

```bash
git add spec/unit/cli_spec.rb
git commit -m "Expand CLI specs: flag parsing and passthrough

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Railtie spec

**Files:**
- Create: `spec/unit/railtie_spec.rb`
- Modify (likely): `activejob-temporal.gemspec` (dev dependency)

**Interfaces:**
- Consumes: `ActiveJob::Temporal::Railtie` (subclass of `Rails::Railtie`, loaded only `if defined?(Rails::Railtie)`); rake task `temporal_jobs:work` reads `QUEUES`/`QUEUE` env or `config.default_task_queue`.
- Constraint: check `bundle exec ruby -e "require 'rails/railtie'"` first; if LoadError, add `spec.add_development_dependency 'railties', '>= 7.2', '< 9.0'` to the gemspec and `bundle install`.

- [ ] **Step 1: Write the spec**

Create `spec/unit/railtie_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'rails/railtie'
require 'active_job/temporal/railtie'
require 'rake'

RSpec.describe ActiveJob::Temporal::Railtie do
  it 'registers the :temporal queue adapter' do
    expect(ActiveJob::QueueAdapters.lookup(:temporal))
      .to be_a(ActiveJob::QueueAdapters::TemporalAdapter)
  end

  describe 'rake task temporal_jobs:work' do
    before do
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      allow(ActiveJob::Temporal::Worker).to receive(:run)
    end

    def load_tasks
      ActiveJob::Temporal::Railtie.rake_tasks_block_source
    end

    it 'splits QUEUES env and runs the worker' do
      skip 'wire railtie rake_tasks block into Rake.application' unless defined?(@tasks_loaded)

      ENV['QUEUES'] = 'a, b'
      Rake::Task['temporal_jobs:work'].invoke
      expect(ActiveJob::Temporal::Worker).to have_received(:run)
        .with(hash_including(queues: %w[a b]))
    ensure
      ENV.delete('QUEUES')
    end

    it 'falls back to the default task queue' do
      skip 'wire railtie rake_tasks block into Rake.application' unless defined?(@tasks_loaded)

      Rake::Task['temporal_jobs:work'].invoke
      expect(ActiveJob::Temporal::Worker).to have_received(:run)
        .with(hash_including(queues: ['default']))
    end
  end
end
```

NOTE for implementer: railtie `rake_tasks` blocks are evaluated by the Rails app, not on require. The cleanest standalone harness is to extract the block: `blocks = described_class.rake_tasks` (Rails stores them in `rake_tasks` array on the class) then `blocks.each { |b| Rake.application.instance_eval(&b) }` inside a `desc`/`namespace` DSL context. Replace the placeholder `skip` guards with the real wiring — the two assertions (env split, default fallback) MUST run for real, not be skipped. If the block cannot be invoked standalone after a genuine attempt, define the rake task inline in the spec mirroring the railtie source exactly, with a comment that it mirrors `railtie.rb`, and add a separate assertion that `railtie.rb` source contains `task :work`.

- [ ] **Step 2: Run spec**

Run: `bundle exec rspec spec/unit/railtie_spec.rb`
Expected: 3 examples, 0 failures (no skips unless documented as above).

- [ ] **Step 3: Commit**

```bash
git add spec/unit/railtie_spec.rb activejob-temporal.gemspec Gemfile.lock
git commit -m "Add Railtie specs (adapter registration, rake task)

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Integration tests — duplicate policy, terminate, multi-queue

**Files:**
- Modify: `spec/integration/end_to_end_spec.rb`

**Interfaces:**
- Consumes: existing `with_worker(queues:)` helper; `ActiveJob::Temporal.cancel/terminate/activity_handle`; verified error class `Temporalio::Error::ActivityAlreadyStartedError`; describe status symbol `:ACTIVITY_EXECUTION_STATUS_TERMINATED`.
- Constraint: dev server must be running.

- [ ] **Step 1: Add the three examples** (append inside the main `RSpec.describe 'ActiveJob on Temporal end-to-end'` block, before its final `end`):

```ruby
  it 'rejects duplicate enqueue with fail conflict policy' do
    stub_const('DupJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-dup'
      temporal_options(id_conflict_policy: :fail)

      def self.name = 'DupJob'
      def perform; end
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = DupJob.new
    adapter.enqueue(job)

    dup = DupJob.new
    dup.define_singleton_method(:job_id) { job.job_id }
    expect { adapter.enqueue(dup) }
      .to raise_error(Temporalio::Error::ActivityAlreadyStartedError)
  end

  it 'terminates a pending activity' do
    stub_const('TermJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-term'

      def self.name = 'TermJob'
      def perform; end
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new
    job = TermJob.new
    adapter.enqueue(job) # no worker: stays pending

    ActiveJob::Temporal.terminate(job.job_id, 'test terminate')

    handle = ActiveJob::Temporal.activity_handle(job.job_id)
    expect { Timeout.timeout(30) { handle.result } }
      .to raise_error(Temporalio::Error::ActivityFailedError)
    expect(handle.describe.raw_info.status).to eq(:ACTIVITY_EXECUTION_STATUS_TERMINATED)
  end

  it 'performs jobs from multiple queues with one worker set' do
    performed = Queue.new

    stub_const('MultiAJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-multi-a'
      define_method(:perform) { performed << :a }
      def self.name = 'MultiAJob'
    end)
    stub_const('MultiBJob', Class.new(ActiveJob::Base) do
      queue_as 'integration-multi-b'
      define_method(:perform) { performed << :b }
      def self.name = 'MultiBJob'
    end)

    adapter = ActiveJob::QueueAdapters::TemporalAdapter.new

    with_worker(queues: %w[integration-multi-a integration-multi-b]) do
      adapter.enqueue(MultiAJob.new)
      adapter.enqueue(MultiBJob.new)

      results = [Timeout.timeout(30) { performed.pop }, Timeout.timeout(30) { performed.pop }]
      expect(results).to contain_exactly(:a, :b)
    end
  end
```

- [ ] **Step 2: Run integration spec**

Run: `PATH="$PATH:/home/node/.temporalio/bin" bundle exec rspec spec/integration/end_to_end_spec.rb`
Expected: 9 examples, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add spec/integration/end_to_end_spec.rb
git commit -m "Add integration tests: duplicate policy, terminate, multi-queue

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Coverage floor verification + cleanup

**Files:**
- Modify (maybe): `spec/spec_helper.rb` (adjust groups only if justified)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run full suite with coverage**

Run: `PATH="$PATH:/home/node/.temporalio/bin" bundle exec rspec`
Expected: 53+ examples, 0 failures, coverage summary printed.

- [ ] **Step 2: Inspect uncovered lines**

Run: `bundle exec ruby -rjson -e 'puts JSON.parse(File.read("coverage/.last_run.json"))'`
If below 95%: inspect `coverage/.resultset.json` for uncovered lines. For genuinely unreachable-in-tests lines (e.g. the `railtie.rb` require guard), either cover them or add `# :nocov:` with a justification comment. Do NOT lower the 95% floor without user sign-off.

- [ ] **Step 3: RuboCop + full check**

Run: `bundle exec rubocop && PATH="$PATH:/home/node/.temporalio/bin" bundle exec rspec`
Expected: no offenses; suite green with coverage >= 95%.

- [ ] **Step 4: Update CHANGELOG**

Append under `[Unreleased]` → `### Added`:

```markdown
- SimpleCov with a 95% line-coverage floor; unit specs for Worker, Railtie,
  CLI, ClientManager, JobOptions, ExecutionActivity; integration tests for
  duplicate-enqueue conflict policy, terminate, and multi-queue workers.
```

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "Verify 95% coverage floor; document in CHANGELOG

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push
```
