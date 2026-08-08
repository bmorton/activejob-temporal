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
require 'active_job'
require 'globalid'
require 'English'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'active_job/temporal'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

ActiveJob::Base.logger = Logger.new(nil)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before do
    ActiveJob::Temporal.reset_configuration!
  end
end
