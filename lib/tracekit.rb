# frozen_string_literal: true

require_relative "tracekit/version"
require_relative "tracekit/config"
require_relative "tracekit/endpoint_resolver"

# Metrics
require_relative "tracekit/metrics/metric_data_point"
require_relative "tracekit/metrics/counter"
require_relative "tracekit/metrics/gauge"
require_relative "tracekit/metrics/histogram"
require_relative "tracekit/metrics/exporter"
require_relative "tracekit/metrics/registry"

# Security
require_relative "tracekit/security/patterns"
require_relative "tracekit/security/detector"

# Local UI
require_relative "tracekit/local_ui_detector"

# Snapshots
require_relative "tracekit/snapshots/models"
require_relative "tracekit/snapshots/client"

# Core SDK
require_relative "tracekit/sdk"
require_relative "tracekit/middleware"

# Rails integration
require_relative "tracekit/railtie" if defined?(Rails::Railtie)

# TraceKit Ruby SDK
# OpenTelemetry-based APM for Ruby and Rails applications
module Tracekit
  class Error < StandardError; end

  # Configures and initializes the TraceKit SDK
  # @example
  #   Tracekit.configure do |config|
  #     config.api_key = ENV["TRACEKIT_API_KEY"]
  #     config.service_name = "my-app"
  #     config.environment = "production"
  #   end
  #
  # @yield [Config::Builder] Configuration builder
  # @return [SDK] Configured SDK instance
  def self.configure
    config = Config.build { |c| yield(c) }
    SDK.configure(config)
  end

  # Returns the current SDK instance
  # @return [SDK, nil]
  def self.sdk
    SDK.current
  end

  # Creates a counter metric
  # @param name [String] Metric name
  # @param tags [Hash] Optional tags
  # @return [Metrics::Counter]
  def self.counter(name, tags = {})
    sdk&.counter(name, tags)
  end

  # Creates a gauge metric
  # @param name [String] Metric name
  # @param tags [Hash] Optional tags
  # @return [Metrics::Gauge]
  def self.gauge(name, tags = {})
    sdk&.gauge(name, tags)
  end

  # Creates a histogram metric
  # @param name [String] Metric name
  # @param tags [Hash] Optional tags
  # @return [Metrics::Histogram]
  def self.histogram(name, tags = {})
    sdk&.histogram(name, tags)
  end

  # Captures a snapshot
  # @param label [String] Snapshot label
  # @param variables [Hash] Variables to capture
  def self.capture_snapshot(label, variables)
    sdk&.capture_snapshot(label, variables)
  end
end
