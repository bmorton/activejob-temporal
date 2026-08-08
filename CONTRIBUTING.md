# Contributing to activejob-temporal

## Development setup

```console
$ bin/setup        # or: bundle install
$ bundle exec appraisal install
```

## Running tests

Unit tests (no server needed):

```console
$ bundle exec rspec spec/unit
```

Integration tests require a Temporal dev server (CLI 1.7+ / Server 1.31+):

```console
$ temporal server start-dev --headless &
$ bundle exec rspec spec/integration
```

Run everything with the CLI on PATH:

```console
$ PATH="$PATH:$HOME/.temporalio/bin" bundle exec rspec
```

## Linting

```console
$ bundle exec rubocop
```

## Conventions

- TDD: write a failing test before implementation code.
- Keep the SDK call surface isolated in the adapter and `ClientManager`.
- The activity name `"ActiveJobExecution"` is part of the public API — changing
  it is a breaking change (in-flight activities reference it).

## Pull requests

- Keep PRs focused; include tests for behavior changes.
- Update CHANGELOG.md under `Unreleased`.
