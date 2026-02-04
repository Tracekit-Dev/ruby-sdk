# frozen_string_literal: true

module Tracekit
  module Metrics
    # Represents a single metric data point for export
    class MetricDataPoint
      attr_reader :name, :type, :value, :tags, :timestamp_nanos

      def initialize(name:, type:, value:, tags:)
        @name = name
        @type = type  # "counter", "gauge", "histogram"
        @value = value
        @tags = tags
        @timestamp_nanos = (Time.now.to_f * 1_000_000_000).to_i
      end
    end
  end
end
