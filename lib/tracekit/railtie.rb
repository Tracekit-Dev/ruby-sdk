# frozen_string_literal: true

module Tracekit
  # Rails integration via Railtie
  # Auto-loads when Rails is detected
  class Railtie < ::Rails::Railtie
    config.tracekit = ActiveSupport::OrderedOptions.new

    initializer "tracekit.configure" do |app|
      # Load configuration from Rails config or ENV vars
      tracekit_config = Config.build do |c|
        c.api_key = app.config.tracekit.api_key || ENV["TRACEKIT_API_KEY"]
        c.service_name = app.config.tracekit.service_name || ENV["TRACEKIT_SERVICE_NAME"] || Rails.application.class.module_parent_name.underscore
        c.endpoint = app.config.tracekit.endpoint || ENV["TRACEKIT_ENDPOINT"] || "app.tracekit.dev"
        c.use_ssl = app.config.tracekit.use_ssl.nil? ? (ENV["TRACEKIT_USE_SSL"] != "false") : app.config.tracekit.use_ssl
        c.environment = app.config.tracekit.environment || ENV["TRACEKIT_ENVIRONMENT"] || Rails.env
        c.service_version = app.config.tracekit.service_version || ENV["TRACEKIT_SERVICE_VERSION"] || "1.0.0"
        c.enable_code_monitoring = app.config.tracekit.enable_code_monitoring.nil? ? (ENV["TRACEKIT_CODE_MONITORING"] != "false") : app.config.tracekit.enable_code_monitoring
        c.code_monitoring_poll_interval = (app.config.tracekit.code_monitoring_poll_interval || ENV["TRACEKIT_POLL_INTERVAL"] || 30).to_i
        c.local_ui_port = (app.config.tracekit.local_ui_port || ENV["TRACEKIT_LOCAL_UI_PORT"] || 9999).to_i
        c.sampling_rate = (app.config.tracekit.sampling_rate || ENV["TRACEKIT_SAMPLING_RATE"] || 1.0).to_f
      end

      # Initialize SDK
      SDK.configure(tracekit_config)

      # Insert middleware
      app.middleware.use Tracekit::Middleware
    end

    # Shutdown SDK when Rails shuts down
    config.after_initialize do
      at_exit { SDK.current&.shutdown }
    end
  end
end
