# frozen_string_literal: true

module Tracekit
  module Security
    # Detects and redacts sensitive data (PII, credentials) from variable snapshots
    class Detector
      SecurityFlag = Struct.new(:type, :category, :severity, :variable, :redacted, keyword_init: true)
      ScanResult = Struct.new(:sanitized_variables, :security_flags, keyword_init: true)

      def scan(variables)
        sanitized = {}
        flags = []

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
        value_str = value.to_s

        # Check PII
        if Patterns::EMAIL.match?(value_str)
          flags << SecurityFlag.new(type: "pii", category: "email", severity: "medium", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::SSN.match?(value_str)
          flags << SecurityFlag.new(type: "pii", category: "ssn", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::CREDIT_CARD.match?(value_str)
          flags << SecurityFlag.new(type: "pii", category: "credit_card", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::PHONE.match?(value_str)
          flags << SecurityFlag.new(type: "pii", category: "phone", severity: "medium", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        # Check Credentials
        if Patterns::API_KEY.match?(value_str)
          flags << SecurityFlag.new(type: "credential", category: "api_key", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::AWS_KEY.match?(value_str)
          flags << SecurityFlag.new(type: "credential", category: "aws_key", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::STRIPE_KEY.match?(value_str)
          flags << SecurityFlag.new(type: "credential", category: "stripe_key", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::PASSWORD.match?(value_str)
          flags << SecurityFlag.new(type: "credential", category: "password", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::JWT.match?(value_str)
          flags << SecurityFlag.new(type: "credential", category: "jwt", severity: "high", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        if Patterns::PRIVATE_KEY.match?(value_str)
          flags << SecurityFlag.new(type: "credential", category: "private_key", severity: "critical", variable: key, redacted: true)
          return ["[REDACTED]", flags]
        end

        [value, flags]
      end
    end
  end
end
