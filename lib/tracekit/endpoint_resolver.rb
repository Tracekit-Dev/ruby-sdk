# frozen_string_literal: true

module Tracekit
  # Resolves endpoint URLs for different TraceKit services (traces, metrics, snapshots)
  # Implements the same logic as .NET, Go, and Java SDKs for consistency
  #
  # CRITICAL: This must match the exact behavior across all SDK implementations
  class EndpointResolver
    class << self
      # Resolves a full endpoint URL from a base endpoint and path
      #
      # @param endpoint [String] The base endpoint (can be host, host with scheme, or full URL)
      # @param path [String] The path to append (e.g., "/v1/traces", "/v1/metrics", or "")
      # @param use_ssl [Boolean] Whether to use HTTPS (ignored if endpoint already has a scheme)
      # @return [String] The resolved endpoint URL
      #
      # @example
      #   resolve("app.tracekit.dev", "/v1/traces", true)
      #   # => "https://app.tracekit.dev/v1/traces"
      #
      #   resolve("http://localhost:8081", "/v1/traces", true)
      #   # => "http://localhost:8081/v1/traces"
      #
      #   resolve("https://app.tracekit.dev/v1/traces", "/v1/metrics", true)
      #   # => "https://app.tracekit.dev/v1/metrics"
      def resolve(endpoint, path, use_ssl)
        # Case 1: Endpoint has a scheme (http:// or https://)
        if endpoint.start_with?("http://", "https://")
          # Remove trailing slash
          endpoint = endpoint.chomp("/")

          # Check if endpoint has a path component (anything after the host)
          without_scheme = endpoint.sub(%r{^https?://}i, "")

          if without_scheme.include?("/")
            # Endpoint has a path component - extract base and append correct path
            base_url = extract_base_url(endpoint)
            return path.empty? ? base_url : "#{base_url}#{path}"
          end

          # Just host with scheme, add the path
          return "#{endpoint}#{path}"
        end

        # Case 2: No scheme provided - build URL with scheme
        scheme = use_ssl ? "https://" : "http://"
        endpoint = endpoint.chomp("/")
        "#{scheme}#{endpoint}#{path}"
      end

      # Extracts base URL (scheme + host + port) from full URL
      # Always strips any path component, regardless of what it is
      #
      # @param full_url [String] The full URL to extract base from
      # @return [String] The base URL (scheme + host + port)
      #
      # @example
      #   extract_base_url("https://app.tracekit.dev/v1/traces")
      #   # => "https://app.tracekit.dev"
      #
      #   extract_base_url("http://localhost:8081/custom/path")
      #   # => "http://localhost:8081"
      def extract_base_url(full_url)
        match = full_url.match(%r{^(https?://[^/]+)})
        match ? match[1] : full_url
      end
    end
  end
end
