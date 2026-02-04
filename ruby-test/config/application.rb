# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module RubyTest
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true

    # TraceKit configuration
    config.tracekit.api_key = ENV["TRACEKIT_API_KEY"] || "test_key"
    config.tracekit.service_name = ENV["TRACEKIT_SERVICE_NAME"] || "ruby-test-app"
    config.tracekit.endpoint = ENV["TRACEKIT_ENDPOINT"] || "http://localhost:8081"
    config.tracekit.environment = ENV["TRACEKIT_ENVIRONMENT"] || "development"
    config.tracekit.enable_code_monitoring = ENV["TRACEKIT_CODE_MONITORING"] != "false"
  end
end
