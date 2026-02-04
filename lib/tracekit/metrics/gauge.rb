# frozen_string_literal: true

module Tracekit
  module Metrics
    # Gauge metric - point-in-time value that can increase or decrease
    # Used for tracking current values like active connections, memory usage, etc.
    class Gauge
      def initialize(name, tags, registry)
        @name = name
        @tags = tags || {}
        @registry = registry
        @value = 0.0
        @mutex = Mutex.new
      end

      # Sets the gauge to a specific value
      # @param value [Numeric] Value to set
      def set(value)
        @mutex.synchronize do
          @value = value
          @registry.record_metric(@name, "gauge", @value, @tags)
        end
      end

      # Increments the gauge by 1
      def inc
        @mutex.synchronize do
          @value += 1
          @registry.record_metric(@name, "gauge", @value, @tags)
        end
      end

      # Decrements the gauge by 1
      def dec
        @mutex.synchronize do
          @value -= 1
          @registry.record_metric(@name, "gauge", @value, @tags)
        end
      end
    end
  end
end
