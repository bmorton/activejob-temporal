# frozen_string_literal: true

require_relative 'lib/active_job/temporal/version'

Gem::Specification.new do |spec|
  spec.name = 'activejob-temporal'
  spec.version = ActiveJob::Temporal::VERSION
  spec.authors = ['Brian Morton']
  spec.email = ['brian@mmmhm.com']

  spec.summary = 'ActiveJob queue adapter backed by Temporal Standalone Activities'
  spec.description = "Maps ActiveJob's perform_later onto Temporal Standalone Activities via the " \
                     'official temporalio Ruby SDK. Durable, retryable background jobs with zero ' \
                     'new infrastructure beyond a worker process.'
  spec.homepage = 'https://github.com/bmorton/activejob-temporal'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'exe/*', 'sig/**/*', 'README.md', 'LICENSE.txt', 'CHANGELOG.md']
  spec.bindir = 'exe'
  spec.executables = ['temporal-jobs']
  spec.require_paths = ['lib']

  # Standalone Activities in the Ruby SDK are experimental; pin a conservative range
  # on a version verified to expose Client#start_activity.
  spec.add_dependency 'activejob', '>= 7.2', '< 9.0'
  spec.add_dependency 'activesupport', '>= 7.2', '< 9.0'
  spec.add_dependency 'temporalio', '>= 1.3', '< 2.0'
end
