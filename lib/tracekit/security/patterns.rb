# frozen_string_literal: true

module Tracekit
  module Security
    # Regex patterns for detecting sensitive data in snapshots
    module Patterns
      # PII Patterns
      EMAIL = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/
      SSN = /\b\d{3}-\d{2}-\d{4}\b/
      CREDIT_CARD = /\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b/
      PHONE = /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/

      # Credential Patterns
      API_KEY = /(api[_-]?key|apikey|access[_-]?key)[\s:=]+['"  ]?([a-zA-Z0-9_-]{20,})['"]?/i
      AWS_KEY = /AKIA[0-9A-Z]{16}/
      STRIPE_KEY = /sk_live_[0-9a-zA-Z]{24}/
      PASSWORD = /(password|pwd|pass)[\s:=]+['" ]?([^\s'" ]{6,})['"]?/i
      JWT = /eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/
      PRIVATE_KEY = /-----BEGIN (RSA |EC )?PRIVATE KEY-----/
    end
  end
end
