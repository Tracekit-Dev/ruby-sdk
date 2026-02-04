# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

# Optional instrumentation - load if available
begin
  require "opentelemetry/instrumentation/http"
rescue LoadError
  # HTTP instrumentation not available
end

begin
  require "opentelemetry/instrumentation/net_http"
rescue LoadError
  # Net::HTTP instrumentation not available
end

begin
  require "opentelemetry/instrumentation/rails"
rescue LoadError
  # Rails instrumentation not available
end

begin
  require "opentelemetry/instrumentation/active_record"
rescue LoadError
  # ActiveRecord instrumentation not available
end

begin
  require "opentelemetry/instrumentation/pg"
rescue LoadError
  # PG instrumentation not available
end

begin
  require "opentelemetry/instrumentation/mysql2"
rescue LoadError
  # MySQL2 instrumentation not available
end

begin
  require "opentelemetry/instrumentation/redis"
rescue LoadError
  # Redis instrumentation not available
end

begin
  require "opentelemetry/instrumentation/sidekiq"
rescue LoadError
  # Sidekiq instrumentation not available
end

begin
  require "opentelemetry/instrumentation/action_view"
rescue LoadError
  # ActionView instrumentation not available
end

begin
  require "opentelemetry/instrumentation/action_pack"
rescue LoadError
  # ActionPack instrumentation not available
end

module Tracekit
  # Main SDK class for TraceKit Ruby SDK with OpenTelemetry integration
  # Provides distributed tracing, metrics collection, and code monitoring capabilities
  class SDK
    attr_reader :config, :service_name

    def initialize(config)
      @config = config
      @service_name = config.service_name

      puts "Initializing TraceKit SDK v#{Tracekit::VERSION} for service: #{config.service_name}, environment: #{config.environment}"

      # Auto-detect local UI
      local_ui_detector = LocalUIDetector.new(config.local_ui_port)
      if local_endpoint = local_ui_detector.local_ui_endpoint
        puts "Local UI detected at #{local_endpoint}"
      end

      # Resolve endpoints
      traces_endpoint = EndpointResolver.resolve(config.endpoint, "/v1/traces", config.use_ssl)
      metrics_endpoint = EndpointResolver.resolve(config.endpoint, "/v1/metrics", config.use_ssl)
      snapshot_base_url = EndpointResolver.resolve(config.endpoint, "", config.use_ssl)

      # Initialize OpenTelemetry tracer
      setup_tracing(traces_endpoint)

      # Initialize metrics registry
      @metrics_registry = Metrics::Registry.new(metrics_endpoint, config.api_key, config.service_name)

      # Initialize snapshot client if code monitoring is enabled
      if config.enable_code_monitoring
        @snapshot_client = Snapshots::Client.new(
          config.api_key,
          snapshot_base_url,
          config.service_name,
          config.code_monitoring_poll_interval
        )
        puts "Code monitoring enabled - Snapshot client started"
      end

      puts "TraceKit SDK initialized successfully. Traces: #{traces_endpoint}, Metrics: #{metrics_endpoint}"
    end

    # Creates a Counter metric for tracking monotonically increasing values
    # @param name [String] Metric name (e.g., "http.requests.total")
    # @param tags [Hash] Optional tags for the metric
    # @return [Metrics::Counter]
    def counter(name, tags = {})
      Metrics::Counter.new(name, tags, @metrics_registry)
    end

    # Creates a Gauge metric for tracking point-in-time values
    # @param name [String] Metric name (e.g., "http.requests.active")
    # @param tags [Hash] Optional tags for the metric
    # @return [Metrics::Gauge]
    def gauge(name, tags = {})
      Metrics::Gauge.new(name, tags, @metrics_registry)
    end

    # Creates a Histogram metric for tracking value distributions
    # @param name [String] Metric name (e.g., "http.request.duration")
    # @param tags [Hash] Optional tags for the metric
    # @return [Metrics::Histogram]
    def histogram(name, tags = {})
      Metrics::Histogram.new(name, tags, @metrics_registry)
    end

    # Captures a snapshot of local variables at the current code location
    # Only active if code monitoring is enabled and there's an active breakpoint
    # @param label [String] Stable identifier for this snapshot location
    # @param variables [Hash] Variables to capture in the snapshot
    def capture_snapshot(label, variables)
      return unless @snapshot_client

      caller_location = caller_locations(1, 1).first
      @snapshot_client.capture_snapshot(label, variables, caller_location)
    end

    # Shuts down the SDK and flushes any pending data
    def shutdown
      @metrics_registry&.shutdown
      @snapshot_client&.shutdown
      OpenTelemetry.tracer_provider&.shutdown
      puts "TraceKit SDK shutdown complete"
    end

    private

    def setup_tracing(traces_endpoint)
      OpenTelemetry::SDK.configure do |c|
        c.service_name = @config.service_name
        c.service_version = @config.service_version

        c.resource = OpenTelemetry::SDK::Resources::Resource.create(
          {
            "service.name" => @config.service_name,
            "service.version" => @config.service_version,
            "deployment.environment" => @config.environment
          }
        )

        # Auto-instrument libraries if available
        # Rails framework
        begin
          c.use "OpenTelemetry::Instrumentation::Rails" if defined?(OpenTelemetry::Instrumentation::Rails)
        rescue StandardError => e
          puts "Rails instrumentation failed: #{e.message}"
        end

        # HTTP clients
        begin
          c.use "OpenTelemetry::Instrumentation::HTTP" if defined?(OpenTelemetry::Instrumentation::HTTP)
        rescue StandardError
          # HTTP instrumentation not available or failed
        end

        begin
          c.use "OpenTelemetry::Instrumentation::NetHTTP" if defined?(OpenTelemetry::Instrumentation::NetHTTP) && defined?(Net::HTTP)
        rescue StandardError
          # NetHTTP instrumentation not available or failed
        end

        # Database - ActiveRecord
        begin
          c.use "OpenTelemetry::Instrumentation::ActiveRecord" if defined?(OpenTelemetry::Instrumentation::ActiveRecord)
        rescue StandardError
          # ActiveRecord instrumentation not available or failed
        end

        # Database - PG (PostgreSQL)
        begin
          c.use "OpenTelemetry::Instrumentation::PG" if defined?(OpenTelemetry::Instrumentation::PG)
        rescue StandardError
          # PG instrumentation not available or failed
        end

        # Database - MySQL2
        begin
          c.use "OpenTelemetry::Instrumentation::Mysql2" if defined?(OpenTelemetry::Instrumentation::Mysql2)
        rescue StandardError
          # MySQL2 instrumentation not available or failed
        end

        # Redis
        begin
          c.use "OpenTelemetry::Instrumentation::Redis" if defined?(OpenTelemetry::Instrumentation::Redis)
        rescue StandardError
          # Redis instrumentation not available or failed
        end

        # Sidekiq
        begin
          c.use "OpenTelemetry::Instrumentation::Sidekiq" if defined?(OpenTelemetry::Instrumentation::Sidekiq)
        rescue StandardError
          # Sidekiq instrumentation not available or failed
        end

        # Rails components
        begin
          c.use "OpenTelemetry::Instrumentation::ActionView" if defined?(OpenTelemetry::Instrumentation::ActionView)
        rescue StandardError
          # ActionView instrumentation not available or failed
        end

        begin
          c.use "OpenTelemetry::Instrumentation::ActionPack" if defined?(OpenTelemetry::Instrumentation::ActionPack)
        rescue StandardError
          # ActionPack instrumentation not available or failed
        end

        c.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
            OpenTelemetry::Exporter::OTLP::Exporter.new(
              endpoint: traces_endpoint,
              headers: { "X-API-Key" => @config.api_key },
              compression: "none"  # Disable compression to match Go SDK default behavior
            )
          )
        )

        # Note: Sampler configuration API changed in OpenTelemetry 1.x
        # For now, using default sampler (ALWAYS_ON)
        # TODO: Implement custom sampler if needed via span processor
      end
    end

    class << self
      # Global SDK instance
      attr_accessor :instance

      # Creates and configures the SDK singleton
      # @param config [Config] SDK configuration
      # @return [SDK]
      def configure(config)
        @instance = new(config)
      end

      # Returns the global SDK instance
      # @return [SDK, nil]
      def current
        @instance
      end
    end
  end
end
