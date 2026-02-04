# frozen_string_literal: true

module Tracekit
  module Metrics
    # Counter metric - monotonically increasing value
    # Used for tracking totals like request counts, error counts, etc.
    class Counter
      def initialize(name, tags, registry)
        @name = name
        @tags = tags || {}
        @registry = registry
        @value = 0.0
        @mutex = Mutex.new
      end

      # Increments the counter by 1
      def inc
        add(1.0)
      end

      # Adds a value to the counter
      # @param value [Numeric] Value to add (must be non-negative)
      def add(value)
        raise ArgumentError, "Counter values must be non-negative" if value < 0

        @mutex.synchronize do
          @value += value
          @registry.record_metric(@name, "counter", @value, @tags)
        end
      end
    end
  end
end
