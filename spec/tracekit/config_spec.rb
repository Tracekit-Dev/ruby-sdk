# frozen_string_literal: true

RSpec.describe Tracekit::Config do
  describe ".build" do
    it "builds config with required fields" do
      config = described_class.build do |c|
        c.api_key = "test_key"
        c.service_name = "test-service"
      end

      expect(config.api_key).to eq("test_key")
      expect(config.service_name).to eq("test-service")
      expect(config.endpoint).to eq("app.tracekit.dev")
      expect(config.use_ssl).to be(true)
      expect(config.environment).to eq("production")
      expect(config.sampling_rate).to eq(1.0)
    end

    it "allows overriding defaults" do
      config = described_class.build do |c|
        c.api_key = "test_key"
        c.service_name = "test-service"
        c.endpoint = "custom.example.com"
        c.use_ssl = false
        c.environment = "staging"
        c.sampling_rate = 0.5
      end

      expect(config.endpoint).to eq("custom.example.com")
      expect(config.use_ssl).to be(false)
      expect(config.environment).to eq("staging")
      expect(config.sampling_rate).to eq(0.5)
    end

    it "raises error when api_key is missing" do
      expect {
        described_class.build do |c|
          c.service_name = "test-service"
        end
      }.to raise_error(ArgumentError, "api_key is required")
    end

    it "raises error when service_name is missing" do
      expect {
        described_class.build do |c|
          c.api_key = "test_key"
        end
      }.to raise_error(ArgumentError, "service_name is required")
    end

    it "raises error for invalid sampling_rate" do
      expect {
        described_class.build do |c|
          c.api_key = "test_key"
          c.service_name = "test-service"
          c.sampling_rate = 1.5
        end
      }.to raise_error(ArgumentError, "sampling_rate must be between 0.0 and 1.0")
    end

    it "makes configuration immutable" do
      config = described_class.build do |c|
        c.api_key = "test_key"
        c.service_name = "test-service"
      end

      expect(config).to be_frozen
    end
  end
end
