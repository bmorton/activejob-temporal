# frozen_string_literal: true

require 'temporalio'
require 'temporalio/priority'

module ActiveJob
  module Temporal
    # Maps ActiveJob priorities (unbounded integers, adapter-defined meaning)
    # onto Temporal's priority_key (1..server-max, lower = higher priority).
    module PriorityMapper
      DEFAULT_SERVER_MAX = 5

      module_function

      # @param value [Integer, Temporalio::Priority, nil]
      # @param max [Integer] server max priority key (Temporal default is 5)
      # @return [Temporalio::Priority, nil]
      def map(value, max: DEFAULT_SERVER_MAX)
        case value
        when nil
          nil
        when Temporalio::Priority
          value
        when Integer
          Temporalio::Priority.new(priority_key: value.clamp(1, max))
        else
          raise ArgumentError, "unsupported priority value: #{value.inspect}"
        end
      end
    end
  end
end
