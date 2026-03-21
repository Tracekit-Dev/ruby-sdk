# frozen_string_literal: true

require "spec_helper"
require "json"
require "tracekit/llm/common"

RSpec.describe Tracekit::LLM::Common do
  let(:span) { instance_double("OpenTelemetry::Trace::Span") }

  before do
    allow(span).to receive(:set_attribute)
    allow(span).to receive(:add_event)
    allow(span).to receive(:status=)
    allow(span).to receive(:record_exception)
  end

  describe ".scrub_pii" do
    context "pattern-based scrubbing" do
      it "replaces email addresses with [REDACTED]" do
        result = described_class.scrub_pii("Contact me at user@example.com for details")
        expect(result).not_to include("user@example.com")
        expect(result).to include("[REDACTED]")
        expect(result).to include("Contact me at")
      end

      it "replaces SSN with [REDACTED]" do
        result = described_class.scrub_pii("SSN: 123-45-6789")
        expect(result).not_to include("123-45-6789")
        expect(result).to include("[REDACTED]")
      end

      it "replaces credit card numbers with [REDACTED]" do
        result = described_class.scrub_pii("Card: 4111-1111-1111-1111")
        expect(result).not_to include("4111-1111-1111-1111")
        expect(result).to include("[REDACTED]")
      end

      it "replaces AWS access keys with [REDACTED]" do
        result = described_class.scrub_pii("Key: AKIAIOSFODNN7EXAMPLE")
        expect(result).not_to include("AKIAIOSFODNN7EXAMPLE")
        expect(result).to include("[REDACTED]")
      end

      it "replaces Bearer tokens with [REDACTED]" do
        result = described_class.scrub_pii("Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U")
        expect(result).not_to include("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
        expect(result).to include("[REDACTED]")
      end

      it "replaces Stripe keys with [REDACTED]" do
        result = described_class.scrub_pii("Stripe key: sk_live_abc123def456ghi")
        expect(result).not_to include("sk_live_abc123def456ghi")
        expect(result).to include("[REDACTED]")
      end

      it "replaces private key headers with [REDACTED]" do
        result = described_class.scrub_pii("-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...")
        expect(result).not_to include("-----BEGIN RSA PRIVATE KEY-----")
        expect(result).to include("[REDACTED]")
      end

      it "returns input unchanged when no PII present" do
        input = "The weather is nice today in San Francisco"
        result = described_class.scrub_pii(input)
        expect(result).to eq(input)
      end

      it "handles mixed content with email, preserving non-PII" do
        result = described_class.scrub_pii("Please send the report to admin@company.com and include the Q4 numbers")
        expect(result).not_to include("admin@company.com")
        expect(result).to include("Q4 numbers")
      end
    end

    context "key-based scrubbing on JSON" do
      it "scrubs password key value" do
        input = '{"username": "john", "password": "secret123"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["password"]).to eq("[REDACTED]")
        expect(parsed["username"]).to eq("john")
      end

      it "scrubs api_key key value" do
        input = '{"api_key": "sk-abc123", "model": "gpt-4o"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["api_key"]).to eq("[REDACTED]")
        expect(parsed["model"]).to eq("gpt-4o")
      end

      it "scrubs nested secret field" do
        input = '{"config": {"secret": "mysecret", "name": "test"}}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["config"]["secret"]).to eq("[REDACTED]")
        expect(parsed["config"]["name"]).to eq("test")
      end

      it "scrubs credential field" do
        input = '{"credential": "abc123", "user": "alice"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["credential"]).to eq("[REDACTED]")
        expect(parsed["user"]).to eq("alice")
      end

      it "scrubs token field" do
        input = '{"token": "tok_xyz", "type": "bearer"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["token"]).to eq("[REDACTED]")
        expect(parsed["type"]).to eq("bearer")
      end

      it "scrubs passwd field" do
        input = '{"passwd": "abc123", "name": "test"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["passwd"]).to eq("[REDACTED]")
      end

      it "scrubs pwd field" do
        input = '{"pwd": "abc123", "name": "test"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["pwd"]).to eq("[REDACTED]")
      end

      it "scrubs apikey field" do
        input = '{"apikey": "abc123", "name": "test"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["apikey"]).to eq("[REDACTED]")
      end

      it "passes through JSON with no sensitive keys" do
        input = '{"model": "gpt-4o", "messages": [{"role": "user", "content": "hello"}]}'
        result = described_class.scrub_pii(input)
        expect(JSON.parse(result)).to eq(JSON.parse(input))
      end
    end

    context "combined key and pattern scrubbing" do
      it "scrubs both key values and patterns in JSON content" do
        input = '{"password": "secret", "message": "Contact user@test.com"}'
        result = described_class.scrub_pii(input)
        parsed = JSON.parse(result)
        expect(parsed["password"]).to eq("[REDACTED]")
        expect(parsed["message"]).not_to include("user@test.com")
      end

      it "scrubs patterns inside array content" do
        input = '[{"role": "user", "content": "My SSN is 123-45-6789 and my email is test@example.com"}]'
        result = described_class.scrub_pii(input)
        expect(result).not_to include("123-45-6789")
        expect(result).not_to include("test@example.com")
        expect(result).to include("role")
        expect(result).to include("content")
      end
    end
  end

  describe ".capture_content?" do
    after { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

    it "returns false by default (env not set)" do
      ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT")
      expect(described_class.capture_content?).to be false
    end

    it "returns true when env is 'true'" do
      ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "true"
      expect(described_class.capture_content?).to be true
    end

    it "returns true when env is '1'" do
      ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "1"
      expect(described_class.capture_content?).to be true
    end

    it "returns false when env is 'false'" do
      ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "false"
      expect(described_class.capture_content?).to be false
    end

    it "returns false when env is '0'" do
      ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "0"
      expect(described_class.capture_content?).to be false
    end
  end

  describe ".set_request_attributes" do
    it "sets required gen_ai request attributes" do
      described_class.set_request_attributes(span, provider: "openai", model: "gpt-4o")
      expect(span).to have_received(:set_attribute).with("gen_ai.operation.name", "chat")
      expect(span).to have_received(:set_attribute).with("gen_ai.system", "openai")
      expect(span).to have_received(:set_attribute).with("gen_ai.request.model", "gpt-4o")
    end

    it "sets optional max_tokens, temperature, top_p when provided" do
      described_class.set_request_attributes(span, provider: "openai", model: "gpt-4o",
                                             max_tokens: 100, temperature: 0.7, top_p: 0.9)
      expect(span).to have_received(:set_attribute).with("gen_ai.request.max_tokens", 100)
      expect(span).to have_received(:set_attribute).with("gen_ai.request.temperature", 0.7)
      expect(span).to have_received(:set_attribute).with("gen_ai.request.top_p", 0.9)
    end

    it "does not set optional attributes when nil" do
      described_class.set_request_attributes(span, provider: "openai", model: "gpt-4o")
      expect(span).not_to have_received(:set_attribute).with("gen_ai.request.max_tokens", anything)
      expect(span).not_to have_received(:set_attribute).with("gen_ai.request.temperature", anything)
      expect(span).not_to have_received(:set_attribute).with("gen_ai.request.top_p", anything)
    end
  end

  describe ".set_response_attributes" do
    it "sets response model, id, finish_reasons, and token counts" do
      described_class.set_response_attributes(span,
                                              model: "gpt-4o-2024-05-13",
                                              id: "chatcmpl-abc123",
                                              finish_reasons: ["stop"],
                                              input_tokens: 10,
                                              output_tokens: 20)
      expect(span).to have_received(:set_attribute).with("gen_ai.response.model", "gpt-4o-2024-05-13")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.id", "chatcmpl-abc123")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.finish_reasons", ["stop"])
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 10)
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.output_tokens", 20)
    end

    it "does not set nil attributes" do
      described_class.set_response_attributes(span)
      expect(span).not_to have_received(:set_attribute)
    end
  end

  describe ".set_error_attributes" do
    it "sets error.type, span status to ERROR, and records exception" do
      error = StandardError.new("something went wrong")
      # We need a real-ish status object
      status_error = double("Status::Error")
      allow(OpenTelemetry::Trace::Status).to receive(:error).with("something went wrong").and_return(status_error)

      described_class.set_error_attributes(span, error)
      expect(span).to have_received(:set_attribute).with("error.type", "StandardError")
      expect(span).to have_received(:status=).with(status_error)
      expect(span).to have_received(:record_exception).with(error)
    end
  end

  describe ".record_tool_call" do
    it "adds gen_ai.tool.call event with name, id, and arguments" do
      described_class.record_tool_call(span, name: "get_weather", id: "call_123", arguments: '{"city":"SF"}')
      expect(span).to have_received(:add_event).with("gen_ai.tool.call", attributes: {
        "gen_ai.tool.name" => "get_weather",
        "gen_ai.tool.call.id" => "call_123",
        "gen_ai.tool.call.arguments" => '{"city":"SF"}'
      })
    end

    it "adds event with only name when id and arguments are nil" do
      described_class.record_tool_call(span, name: "get_weather")
      expect(span).to have_received(:add_event).with("gen_ai.tool.call", attributes: {
        "gen_ai.tool.name" => "get_weather"
      })
    end
  end

  describe ".capture_input_messages" do
    it "sets gen_ai.input.messages with PII scrubbed" do
      messages = [{ "role" => "user", "content" => "Email: user@test.com" }]
      described_class.capture_input_messages(span, messages)
      expect(span).to have_received(:set_attribute).with("gen_ai.input.messages", anything) do |_, val|
        expect(val).not_to include("user@test.com")
        expect(val).to include("[REDACTED]")
      end
    end

    it "does nothing when messages is nil" do
      described_class.capture_input_messages(span, nil)
      expect(span).not_to have_received(:set_attribute)
    end
  end

  describe ".capture_output_messages" do
    it "sets gen_ai.output.messages with PII scrubbed" do
      content = [{ "role" => "assistant", "content" => "Call user@test.com" }]
      described_class.capture_output_messages(span, content)
      expect(span).to have_received(:set_attribute).with("gen_ai.output.messages", anything) do |_, val|
        expect(val).not_to include("user@test.com")
      end
    end
  end

  describe ".capture_system_instructions" do
    it "sets gen_ai.system_instructions with PII scrubbed" do
      described_class.capture_system_instructions(span, "You are a helpful assistant. Contact admin@test.com")
      expect(span).to have_received(:set_attribute).with("gen_ai.system_instructions", anything) do |_, val|
        expect(val).not_to include("admin@test.com")
      end
    end

    it "does nothing when system is nil" do
      described_class.capture_system_instructions(span, nil)
      expect(span).not_to have_received(:set_attribute)
    end
  end
end
