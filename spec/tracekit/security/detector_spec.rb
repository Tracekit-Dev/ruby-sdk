# frozen_string_literal: true

RSpec.describe Tracekit::Security::Detector do
  subject(:detector) { described_class.new }

  describe "#scan" do
    it "detects email addresses" do
      variables = { "email" => "user@example.com" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["email"]).to eq("[REDACTED]")
      expect(result.security_flags.size).to eq(1)
      expect(result.security_flags.first.type).to eq("pii")
      expect(result.security_flags.first.category).to eq("email")
      expect(result.security_flags.first.severity).to eq("medium")
    end

    it "detects SSN" do
      variables = { "ssn" => "123-45-6789" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["ssn"]).to eq("[REDACTED]")
      expect(result.security_flags.first.category).to eq("ssn")
      expect(result.security_flags.first.severity).to eq("critical")
    end

    it "detects credit card numbers" do
      variables = { "card" => "4111 1111 1111 1111" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["card"]).to eq("[REDACTED]")
      expect(result.security_flags.first.category).to eq("credit_card")
      expect(result.security_flags.first.severity).to eq("critical")
    end

    it "detects phone numbers" do
      variables = { "phone" => "555-123-4567" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["phone"]).to eq("[REDACTED]")
      expect(result.security_flags.first.category).to eq("phone")
      expect(result.security_flags.first.severity).to eq("medium")
    end

    it "detects API keys" do
      variables = { "config" => "api_key=sk_test_1234567890abcdefghij" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["config"]).to eq("[REDACTED]")
      expect(result.security_flags.first.type).to eq("credential")
      expect(result.security_flags.first.category).to eq("api_key")
      expect(result.security_flags.first.severity).to eq("critical")
    end

    it "detects AWS keys" do
      variables = { "aws" => "AKIAIOSFODNN7EXAMPLE" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["aws"]).to eq("[REDACTED]")
      expect(result.security_flags.first.category).to eq("aws_key")
      expect(result.security_flags.first.severity).to eq("critical")
    end

    it "detects passwords" do
      variables = { "pass" => "password=secret123" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["pass"]).to eq("[REDACTED]")
      expect(result.security_flags.first.category).to eq("password")
      expect(result.security_flags.first.severity).to eq("critical")
    end

    it "detects JWT tokens" do
      variables = { "token" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U" }
      result = detector.scan(variables)

      expect(result.sanitized_variables["token"]).to eq("[REDACTED]")
      expect(result.security_flags.first.category).to eq("jwt")
      expect(result.security_flags.first.severity).to eq("high")
    end

    it "handles null values" do
      variables = { "null_value" => nil }
      result = detector.scan(variables)

      expect(result.sanitized_variables["null_value"]).to eq("[NULL]")
      expect(result.security_flags).to be_empty
    end

    it "passes through safe values" do
      variables = { "userId" => 123, "amount" => 99.99, "status" => "active" }
      result = detector.scan(variables)

      expect(result.sanitized_variables).to eq(variables)
      expect(result.security_flags).to be_empty
    end
  end
end
