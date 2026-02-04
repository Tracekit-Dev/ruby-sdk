# frozen_string_literal: true

RSpec.describe Tracekit::EndpointResolver do
  describe ".resolve" do
    # Test 1: Host only with SSL
    it "resolves host only with SSL to HTTPS URL" do
      result = described_class.resolve("app.tracekit.dev", "/v1/traces", true)
      expect(result).to eq("https://app.tracekit.dev/v1/traces")
    end

    # Test 2: Host only without SSL
    it "resolves host only without SSL to HTTP URL" do
      result = described_class.resolve("localhost:8081", "/v1/traces", false)
      expect(result).to eq("http://localhost:8081/v1/traces")
    end

    # Test 3: HTTP scheme ignores SSL flag
    it "ignores SSL flag when HTTP scheme is present" do
      result = described_class.resolve("http://localhost:8081", "/v1/traces", true)
      expect(result).to eq("http://localhost:8081/v1/traces")
    end

    # Test 4: HTTPS scheme ignores SSL flag
    it "ignores SSL flag when HTTPS scheme is present" do
      result = described_class.resolve("https://app.tracekit.dev", "/v1/metrics", false)
      expect(result).to eq("https://app.tracekit.dev/v1/metrics")
    end

    # Test 5: Full URL with path - extracts base and appends new path
    it "extracts base URL and appends new path when full URL provided" do
      result = described_class.resolve("http://localhost:8081/v1/traces", "/v1/metrics", true)
      expect(result).to eq("http://localhost:8081/v1/metrics")
    end

    # Test 6: Complex path - extracts base and appends new path
    it "extracts base from complex path and appends new path" do
      result = described_class.resolve("https://app.tracekit.dev/api/v2/", "/v1/traces", false)
      expect(result).to eq("https://app.tracekit.dev/v1/traces")
    end

    # Test 7: Empty path returns base only
    it "returns base URL when path is empty" do
      result = described_class.resolve("app.tracekit.dev", "", true)
      expect(result).to eq("https://app.tracekit.dev")
    end

    # Test 8: Full URL with empty path - extracts base
    it "extracts base URL when full URL provided with empty path" do
      result = described_class.resolve("http://localhost:8081/v1/traces", "", true)
      expect(result).to eq("http://localhost:8081")
    end

    # Test 9: Trailing slash removed
    it "removes trailing slash from endpoint" do
      result = described_class.resolve("app.tracekit.dev/", "/v1/metrics", true)
      expect(result).to eq("https://app.tracekit.dev/v1/metrics")
    end
  end

  describe ".extract_base_url" do
    it "extracts scheme and host from full URL" do
      result = described_class.extract_base_url("https://app.tracekit.dev/v1/traces")
      expect(result).to eq("https://app.tracekit.dev")
    end

    it "extracts scheme and host from localhost URL" do
      result = described_class.extract_base_url("http://localhost:8081/custom/path")
      expect(result).to eq("http://localhost:8081")
    end
  end
end
