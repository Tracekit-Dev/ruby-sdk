# frozen_string_literal: true

require "net/http"

module Tracekit
  module LocalUI
    # Detects if TraceKit Local UI is running and provides the endpoint
    class Detector
      def initialize(port = 9999)
        @port = port
      end

      # Checks if Local UI is running by attempting a health check
      # @return [Boolean] true if Local UI is running
      def running?
        uri = URI("http://localhost:#{@port}/api/health")
        response = Net::HTTP.get_response(uri)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      # Gets the Local UI endpoint if it's running, otherwise nil
      # @return [String, nil] The endpoint or nil
      def endpoint
        running? ? "http://localhost:#{@port}" : nil
      end
    end
  end
end
