# frozen_string_literal: true

require 'rails/railtie'

module ActiveJob
  module Temporal
    class Railtie < Rails::Railtie
      rake_tasks do
        namespace :temporal_jobs do
          desc 'Run Temporal workers polling ActiveJob queues'
          task :work, [:queues] => :environment do |_t, args|
            queues = (args[:queues] || ENV['QUEUES'] || ENV['QUEUE'] ||
                      ActiveJob::Temporal.config.default_task_queue).split(',').map(&:strip)
            ActiveJob::Temporal::Worker.run(
              queues: queues,
              concurrency: ENV['CONCURRENCY']&.to_i
            )
          end
        end
      end
    end
  end
end
