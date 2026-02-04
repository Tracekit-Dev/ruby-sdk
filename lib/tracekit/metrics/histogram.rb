# frozen_string_literal: true

module Tracekit
  module Metrics
    # Histogram metric - records distribution of values
    # Used for tracking request durations, payload sizes, etc.
    class Histogram
      def initialize(name, tags, registry)
        @name = name
        @tags = tags || {}
        @registry = registry
      end

      # Records a value in the histogram
      # @param value [Numeric] Value to record
      def record(value)
        @registry.record_metric(@name, "histogram", value, @tags)
      end
    end
  end
end
