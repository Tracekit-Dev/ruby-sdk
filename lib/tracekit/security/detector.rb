# frozen_string_literal: true

module Tracekit
  module Security
    # Detects and redacts sensitive data (PII, credentials) from variable snapshots.
    # Uses typed [REDACTED:type] markers. PII scrubbing is enabled by default.
    class Detector
      SecurityFlag = Struct.new(:type, :category, :severity, :variable, :redacted, keyword_init: true)
      ScanResult = Struct.new(:sanitized_variables, :security_flags, keyword_init: true)

      attr_accessor :pii_scrubbing

      # @param pii_scrubbing [Boolean] whether PII scrubbing is enabled (default: true)
      # @param custom_patterns [Array<Hash>] custom patterns, each with :pattern (Regexp) and :marker (String)
      def initialize(pii_scrubbing: true, custom_patterns: [])
        @pii_scrubbing = pii_scrubbing
        @custom_patterns = custom_patterns.map { |p| [p[:pattern], p[:marker]] }
      end

      def scan(variables)
        sanitized = {}
        flags = []

        # If PII scrubbing is disabled, return as-is
        unless @pii_scrubbing
          return ScanResult.new(sanitized_variables: variables.dup, security_flags: [])
        end

        variables.each do |key, value|
          sanitized_value, detected_flags = scan_value(key, value)
          sanitized[key] = sanitized_value
          flags.concat(detected_flags)
        end

        ScanResult.new(sanitized_variables: sanitized, security_flags: flags)
      end

      private

      def scan_value(key, value)
        return ["[NULL]", []] if value.nil?

        flags = []

        # Check variable name for sensitive keywords (word-boundary matching)
        if Patterns::SENSITIVE_NAME.match?(key.to_s)
          flags << SecurityFlag.new(type: "sensitive_name", category: "name", severity: "medium", variable: key, redacted: true)
          return ["[REDACTED:sensitive_name]", flags]
        end

        # Serialize value to string for deep scanning
        value_str = value.to_s

        # Check built-in patterns with typed markers
        Patterns::PATTERN_MARKERS.each do |pattern, marker|
          if pattern.match?(value_str)
            category = marker.match(/REDACTED:(\w+)/)[1]
            flags << SecurityFlag.new(type: "sensitive_data", category: category, severity: "high", variable: key, redacted: true)
            return [marker, flags]
          end
        end

        # Check custom patterns
        @custom_patterns.each do |pattern, marker|
          if pattern.match?(value_str)
            flags << SecurityFlag.new(type: "custom", category: "custom", severity: "high", variable: key, redacted: true)
            return [marker, flags]
          end
        end

        [value, flags]
      end
    end
  end
end
