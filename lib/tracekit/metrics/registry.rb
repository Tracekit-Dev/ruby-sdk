# frozen_string_literal: true

require "concurrent/array"
require "concurrent/timer_task"

module Tracekit
  module Metrics
    # Registry for managing metrics and exporting them to TraceKit
    # Implements automatic buffering and periodic export (100 metrics or 10 seconds)
    class Registry
      MAX_BUFFER_SIZE = 100
      FLUSH_INTERVAL_SECONDS = 10

      def initialize(endpoint, api_key, service_name)
        @endpoint = endpoint
        @api_key = api_key
        @service_name = service_name
        @buffer = Concurrent::Array.new
        @exporter = Exporter.new(endpoint, api_key, service_name)
        @flush_mutex = Mutex.new

        # Start periodic flush timer
        @flush_task = Concurrent::TimerTask.new(execution_interval: FLUSH_INTERVAL_SECONDS) do
          flush
        end
        @flush_task.execute
      end

      # Records a metric data point
      def record_metric(name, type, value, tags)
        data_point = MetricDataPoint.new(
          name: name,
          type: type,
          value: value,
          tags: tags.dup
        )

        @buffer << data_point

        # Auto-flush if buffer is full
        flush if @buffer.size >= MAX_BUFFER_SIZE
      end

      # Flushes all buffered metrics
      def flush
        return if @buffer.empty?

        @flush_mutex.synchronize do
          return if @buffer.empty?

          data_points = @buffer.dup
          @buffer.clear

          begin
            @exporter.export(data_points)
          rescue => e
            warn "Failed to export metrics: #{e.message}"
          end
        end
      end

      # Shuts down the registry and flushes remaining metrics
      def shutdown
        @flush_task&.shutdown
        flush
      end
    end
  end
end
