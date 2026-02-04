# frozen_string_literal: true

# TraceKit SDK initialization for ruby-test application
# The Railtie will automatically configure the SDK using ENV variables
# This file is here for documentation purposes and optional manual configuration

# The SDK will be auto-configured with:
# - TRACEKIT_API_KEY (required)
# - TRACEKIT_ENDPOINT (default: app.tracekit.dev)
# - TRACEKIT_SERVICE_NAME (default: ruby-test-app)
# - TRACEKIT_ENVIRONMENT (default: development)
# - TRACEKIT_CODE_MONITORING (default: true)

# For manual configuration (uncomment if needed):
# Tracekit.configure do |config|
#   config.api_key = ENV["TRACEKIT_API_KEY"]
#   config.service_name = "ruby-test-app"
#   config.endpoint = ENV.fetch("TRACEKIT_ENDPOINT", "app.tracekit.dev")
#   config.environment = Rails.env
#   config.enable_code_monitoring = true
# end
