# frozen_string_literal: true

require 'rails/generators'

module ActiveJob
  module Temporal
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path('templates', __dir__)

        def create_initializer
          template 'initializer.rb.tt', 'config/initializers/active_job_temporal.rb'
        end

        def create_procfile
          template 'Procfile.temporal.tt', 'Procfile.temporal'
        end

        def print_next_steps
          say_status :next_steps,
                     'Set queue_adapter = :temporal and run: bin/temporal-jobs -q default'
        end
      end
    end
  end
end
