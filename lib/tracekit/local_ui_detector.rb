# frozen_string_literal: true

require "net/http"
require "timeout"

module Tracekit
  # Detects if TraceKit Local UI is running on the developer's machine
  class LocalUIDetector
    attr_reader :port

    def initialize(port = 9999)
      @port = port
    end

    # Check if local UI is running by hitting the health endpoint
    # @return [Boolean] true if local UI is accessible
    def local_ui_running?
      Timeout.timeout(0.5) do
        uri = URI("http://localhost:#{@port}/api/health")
        response = Net::HTTP.get_response(uri)
        response.is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
    end

    # Get the local UI endpoint if running
    # @return [String, nil] the endpoint URL or nil if not running
    def local_ui_endpoint
      local_ui_running? ? "http://localhost:#{@port}" : nil
    end
  end
end
