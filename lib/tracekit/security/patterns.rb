# frozen_string_literal: true

module Tracekit
  module Security
    # Regex patterns for detecting sensitive data in snapshots.
    # 13 standard patterns with typed [REDACTED:type] markers.
    module Patterns
      # PII Patterns
      EMAIL = /\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/
      SSN = /\b\d{3}-\d{2}-\d{4}\b/
      CREDIT_CARD = /\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b/
      PHONE = /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/

      # Credential Patterns
      API_KEY = /(?:api[_\-]?key|apikey)\s*[:=]\s*['"]?[A-Za-z0-9_\-]{20,}/i
      AWS_KEY = /AKIA[0-9A-Z]{16}/
      AWS_SECRET = /aws.{0,20}secret.{0,20}[A-Za-z0-9\/+=]{40}/i
      OAUTH_TOKEN = /(?:bearer\s+)[A-Za-z0-9._~+\/=\-]{20,}/i
      STRIPE_KEY = /sk_live_[0-9a-zA-Z]{10,}/
      PASSWORD = /(?:password|passwd|pwd)\s*[=:]\s*['"]?[^\s'"]{6,}/i
      JWT = /eyJ[a-zA-Z0-9_\-]+\.eyJ[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+/
      PRIVATE_KEY = /-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/

      # Letter-boundary pattern -- \b treats _ as word char, so api_key/user_token won't match
      SENSITIVE_NAME = /(?:^|[^a-zA-Z])(?:password|passwd|pwd|secret|token|key|credential|api_key|apikey)(?:[^a-zA-Z]|$)/i

      # Mapping of pattern -> typed redaction marker
      PATTERN_MARKERS = {
        EMAIL => "[REDACTED:email]",
        SSN => "[REDACTED:ssn]",
        CREDIT_CARD => "[REDACTED:credit_card]",
        PHONE => "[REDACTED:phone]",
        AWS_KEY => "[REDACTED:aws_key]",
        AWS_SECRET => "[REDACTED:aws_secret]",
        OAUTH_TOKEN => "[REDACTED:oauth_token]",
        STRIPE_KEY => "[REDACTED:stripe_key]",
        PASSWORD => "[REDACTED:password]",
        JWT => "[REDACTED:jwt]",
        PRIVATE_KEY => "[REDACTED:private_key]",
        API_KEY => "[REDACTED:api_key]"
      }.freeze
    end
  end
end
