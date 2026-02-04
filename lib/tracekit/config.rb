# frozen_string_literal: true

module Tracekit
  # Configuration for the TraceKit SDK
  # Follows the builder pattern with sensible defaults
  class Config
    attr_reader :api_key, :service_name, :endpoint, :use_ssl, :environment,
                :service_version, :enable_code_monitoring,
                :code_monitoring_poll_interval, :local_ui_port, :sampling_rate

    def initialize(builder)
      @api_key = builder.api_key
      @service_name = builder.service_name
      @endpoint = builder.endpoint || "app.tracekit.dev"
      @use_ssl = builder.use_ssl.nil? ? true : builder.use_ssl
      @environment = builder.environment || "production"
      @service_version = builder.service_version || "1.0.0"
      @enable_code_monitoring = builder.enable_code_monitoring.nil? ? true : builder.enable_code_monitoring
      @code_monitoring_poll_interval = builder.code_monitoring_poll_interval || 30
      @local_ui_port = builder.local_ui_port || 9999
      @sampling_rate = builder.sampling_rate || 1.0

      validate!
      freeze # Make configuration immutable
    end

    # Builder pattern for fluent API
    def self.build
      builder = Builder.new
      yield(builder) if block_given?
      new(builder)
    end

    # Builder class for constructing Config instances
    class Builder
      attr_accessor :api_key, :service_name, :endpoint, :use_ssl, :environment,
                    :service_version, :enable_code_monitoring,
                    :code_monitoring_poll_interval, :local_ui_port, :sampling_rate

      def initialize
        # Set defaults in builder
        @endpoint = "app.tracekit.dev"
        @use_ssl = true
        @environment = "production"
        @service_version = "1.0.0"
        @enable_code_monitoring = true
        @code_monitoring_poll_interval = 30
        @local_ui_port = 9999
        @sampling_rate = 1.0
      end
    end

    private

    def validate!
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.to_s.empty?
      raise ArgumentError, "service_name is required" if service_name.nil? || service_name.to_s.empty?
      raise ArgumentError, "sampling_rate must be between 0.0 and 1.0" unless (0.0..1.0).cover?(sampling_rate)
    end
  end
end
