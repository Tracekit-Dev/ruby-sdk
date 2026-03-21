# frozen_string_literal: true

require "spec_helper"
require "json"
require "tracekit/llm/common"

# Shared tracer that can be reconfigured per test
class AnthropicTestTracer
  attr_accessor :current_span

  def start_span(name, kind: nil)
    current_span
  end
end

# Mock Anthropic gem structure
module Anthropic
  class Client
    class Messages
      class << self
        attr_accessor :mock_response
      end

      def create(**params)
        self.class.mock_response || default_response
      end

      private

      def default_response
        {
          "id" => "msg_abc123",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-sonnet-4-20250514",
          "content" => [
            { "type" => "text", "text" => "Hello!" }
          ],
          "stop_reason" => "end_turn",
          "usage" => { "input_tokens" => 12, "output_tokens" => 8 }
        }
      end
    end
  end
end

require "tracekit/llm/anthropic_instrumentation"

# Install once with our shared tracer
ANTHROPIC_TEST_TRACER = AnthropicTestTracer.new
Tracekit::LLM::AnthropicInstrumentation.install(ANTHROPIC_TEST_TRACER)

RSpec.describe Tracekit::LLM::AnthropicInstrumentation do
  let(:span) do
    s = instance_double("OpenTelemetry::Trace::Span")
    allow(s).to receive(:set_attribute)
    allow(s).to receive(:add_event)
    allow(s).to receive(:status=)
    allow(s).to receive(:record_exception)
    allow(s).to receive(:finish)
    s
  end

  before do
    ANTHROPIC_TEST_TRACER.current_span = span
    Anthropic::Client::Messages.mock_response = nil
    ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT")
  end

  describe ".install" do
    it "prepends to Anthropic::Client::Messages" do
      expect(Anthropic::Client::Messages.ancestors.first).not_to eq(Anthropic::Client::Messages)
    end
  end

  context "non-streaming chat" do
    let(:messages) { Anthropic::Client::Messages.new }

    it "creates a span and sets gen_ai request attributes" do
      messages.create(model: "claude-sonnet-4-20250514", messages: [{ role: "user", content: "Hi" }], max_tokens: 1024)

      expect(span).to have_received(:set_attribute).with("gen_ai.operation.name", "chat")
      expect(span).to have_received(:set_attribute).with("gen_ai.system", "anthropic")
      expect(span).to have_received(:set_attribute).with("gen_ai.request.model", "claude-sonnet-4-20250514")
      expect(span).to have_received(:set_attribute).with("gen_ai.request.max_tokens", 1024)
    end

    it "sets response attributes from the result" do
      messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024)

      expect(span).to have_received(:set_attribute).with("gen_ai.response.model", "claude-sonnet-4-20250514")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.id", "msg_abc123")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.finish_reasons", ["end_turn"])
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 12)
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.output_tokens", 8)
    end

    it "finishes the span after response" do
      messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024)
      expect(span).to have_received(:finish)
    end

    it "sets optional temperature and top_p" do
      messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, temperature: 0.7, top_p: 0.9)

      expect(span).to have_received(:set_attribute).with("gen_ai.request.temperature", 0.7)
      expect(span).to have_received(:set_attribute).with("gen_ai.request.top_p", 0.9)
    end

    context "with cache tokens" do
      before do
        Anthropic::Client::Messages.mock_response = {
          "id" => "msg_cache1",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-sonnet-4-20250514",
          "content" => [{ "type" => "text", "text" => "Cached!" }],
          "stop_reason" => "end_turn",
          "usage" => {
            "input_tokens" => 10,
            "output_tokens" => 5,
            "cache_creation_input_tokens" => 100,
            "cache_read_input_tokens" => 50
          }
        }
      end

      it "records cache tokens as gen_ai.usage.cache_* attributes" do
        messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024)

        expect(span).to have_received(:set_attribute).with("gen_ai.usage.cache_creation.input_tokens", 100)
        expect(span).to have_received(:set_attribute).with("gen_ai.usage.cache_read.input_tokens", 50)
      end
    end

    context "with tool_use content blocks" do
      before do
        Anthropic::Client::Messages.mock_response = {
          "id" => "msg_tool1",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-sonnet-4-20250514",
          "content" => [
            {
              "type" => "tool_use",
              "id" => "toolu_abc123",
              "name" => "get_weather",
              "input" => { "city" => "SF" }
            }
          ],
          "stop_reason" => "tool_use",
          "usage" => { "input_tokens" => 15, "output_tokens" => 20 }
        }
      end

      it "records tool calls as gen_ai.tool.call span events" do
        messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024)

        expect(span).to have_received(:add_event).with("gen_ai.tool.call", attributes: {
          "gen_ai.tool.name" => "get_weather",
          "gen_ai.tool.call.id" => "toolu_abc123",
          "gen_ai.tool.call.arguments" => '{"city":"SF"}'
        })
      end
    end

    context "when capture_content is enabled" do
      before { ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "true" }
      after { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

      it "captures system instructions" do
        messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, system: "You are a helper")

        expect(span).to have_received(:set_attribute).with("gen_ai.system_instructions", anything)
      end

      it "captures input messages" do
        messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024,
                        messages: [{ role: "user", content: "Hello" }])

        expect(span).to have_received(:set_attribute).with("gen_ai.input.messages", anything)
      end

      it "captures output messages" do
        messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024)

        expect(span).to have_received(:set_attribute).with("gen_ai.output.messages", anything)
      end
    end

    context "when capture_content is disabled" do
      before { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

      it "does not capture input or output messages" do
        messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024,
                        messages: [{ role: "user", content: "Hello" }])

        expect(span).not_to have_received(:set_attribute).with("gen_ai.input.messages", anything)
        expect(span).not_to have_received(:set_attribute).with("gen_ai.output.messages", anything)
      end
    end

    context "on error" do
      before do
        Anthropic::Client::Messages.define_method(:default_response) do
          raise StandardError, "API error"
        end
      end

      after do
        Anthropic::Client::Messages.define_method(:default_response) do
          {
            "id" => "msg_abc123",
            "type" => "message",
            "role" => "assistant",
            "model" => "claude-sonnet-4-20250514",
            "content" => [{ "type" => "text", "text" => "Hello!" }],
            "stop_reason" => "end_turn",
            "usage" => { "input_tokens" => 12, "output_tokens" => 8 }
          }
        end
      end

      it "sets error attributes and re-raises" do
        status_error = double("Status::Error")
        allow(OpenTelemetry::Trace::Status).to receive(:error).and_return(status_error)

        expect { messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024) }.to raise_error(StandardError, "API error")
        expect(span).to have_received(:set_attribute).with("error.type", "StandardError")
        expect(span).to have_received(:status=).with(status_error)
        expect(span).to have_received(:record_exception)
        expect(span).to have_received(:finish)
      end
    end
  end

  context "streaming chat" do
    let(:messages) { Anthropic::Client::Messages.new }

    let(:standard_events) do
      [
        { "type" => "message_start", "message" => { "id" => "msg_s1", "model" => "claude-sonnet-4-20250514", "usage" => { "input_tokens" => 15 } } },
        { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "text", "text" => "" } },
        { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "text_delta", "text" => "Hel" } },
        { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "text_delta", "text" => "lo!" } },
        { "type" => "message_delta", "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 10 } }
      ]
    end

    before do
      Anthropic::Client::Messages.mock_response = standard_events.each
    end

    it "returns an AnthropicStreamWrapper" do
      result = messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, stream: true)
      expect(result).to be_a(Tracekit::LLM::AnthropicInstrumentation::AnthropicStreamWrapper)
    end

    it "finalizes span with accumulated token counts after consuming stream" do
      result = messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, stream: true)
      result.each { |_event| }

      expect(span).to have_received(:set_attribute).with("gen_ai.response.model", "claude-sonnet-4-20250514")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.id", "msg_s1")
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 15)
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.output_tokens", 10)
      expect(span).to have_received(:set_attribute).with("gen_ai.response.finish_reasons", ["end_turn"])
      expect(span).to have_received(:finish)
    end

    context "with cache tokens in message_start" do
      before do
        events = [
          { "type" => "message_start", "message" => { "id" => "msg_c1", "model" => "claude-sonnet-4-20250514", "usage" => { "input_tokens" => 15, "cache_creation_input_tokens" => 200, "cache_read_input_tokens" => 75 } } },
          { "type" => "message_delta", "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 5 } }
        ]
        Anthropic::Client::Messages.mock_response = events.each
      end

      it "records cache tokens from streaming events" do
        result = messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, stream: true)
        result.each { |_| }

        expect(span).to have_received(:set_attribute).with("gen_ai.usage.cache_creation.input_tokens", 200)
        expect(span).to have_received(:set_attribute).with("gen_ai.usage.cache_read.input_tokens", 75)
      end
    end

    context "with tool_use content blocks in stream" do
      before do
        events = [
          { "type" => "message_start", "message" => { "id" => "msg_t1", "model" => "claude-sonnet-4-20250514", "usage" => { "input_tokens" => 20 } } },
          { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "tool_use", "id" => "toolu_s1", "name" => "get_weather" } },
          { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "input_json_delta", "partial_json" => '{"ci' } },
          { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "input_json_delta", "partial_json" => 'ty":"SF"}' } },
          { "type" => "message_delta", "delta" => { "stop_reason" => "tool_use" }, "usage" => { "output_tokens" => 15 } }
        ]
        Anthropic::Client::Messages.mock_response = events.each
      end

      it "accumulates tool call deltas and records as events on finalize" do
        result = messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, stream: true)
        result.each { |_| }

        expect(span).to have_received(:add_event).with("gen_ai.tool.call", attributes: {
          "gen_ai.tool.name" => "get_weather",
          "gen_ai.tool.call.id" => "toolu_s1",
          "gen_ai.tool.call.arguments" => '{"city":"SF"}'
        })
      end
    end

    context "when capture_content is enabled" do
      before do
        ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "true"
        Anthropic::Client::Messages.mock_response = standard_events.each
      end
      after { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

      it "accumulates content deltas and sets on span at end" do
        result = messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, stream: true)
        result.each { |_| }

        expect(span).to have_received(:set_attribute).with("gen_ai.output.messages", anything)
      end
    end

    context "on stream error" do
      before do
        error_enum = Enumerator.new do |y|
          y << { "type" => "message_start", "message" => { "id" => "msg_err", "model" => "claude-sonnet-4-20250514", "usage" => { "input_tokens" => 5 } } }
          raise StandardError, "Stream error"
        end
        Anthropic::Client::Messages.mock_response = error_enum
      end

      it "sets error attributes and re-raises on stream error" do
        status_error = double("Status::Error")
        allow(OpenTelemetry::Trace::Status).to receive(:error).and_return(status_error)

        result = messages.create(model: "claude-sonnet-4-20250514", max_tokens: 1024, stream: true)
        expect { result.each { |_| } }.to raise_error(StandardError, "Stream error")
        expect(span).to have_received(:set_attribute).with("error.type", "StandardError")
        expect(span).to have_received(:finish)
      end
    end
  end
end
