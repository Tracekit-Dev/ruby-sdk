# frozen_string_literal: true

require "spec_helper"
require "json"
require "tracekit/llm/common"

# Shared tracer that can be reconfigured per test
class TestTracer
  attr_accessor :current_span

  def start_span(name, kind: nil)
    current_span
  end
end

# Mock OpenAI module - uses class-level response override for testing
module OpenAI
  class Client
    class << self
      attr_accessor :mock_response
    end

    def chat(parameters: {})
      self.class.mock_response || default_response
    end

    private

    def default_response
      {
        "id" => "chatcmpl-abc123",
        "model" => "gpt-4o-2024-05-13",
        "choices" => [
          {
            "message" => { "role" => "assistant", "content" => "Hello!" },
            "finish_reason" => "stop"
          }
        ],
        "usage" => { "prompt_tokens" => 10, "completion_tokens" => 20 }
      }
    end
  end
end

require "tracekit/llm/openai_instrumentation"

# Install once with our shared tracer
TEST_TRACER = TestTracer.new
Tracekit::LLM::OpenAIInstrumentation.install(TEST_TRACER)

RSpec.describe Tracekit::LLM::OpenAIInstrumentation do
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
    TEST_TRACER.current_span = span
    OpenAI::Client.mock_response = nil
    ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT")
  end

  describe ".install" do
    it "prepends to OpenAI::Client" do
      expect(OpenAI::Client.ancestors.first).not_to eq(OpenAI::Client)
    end
  end

  context "non-streaming chat" do
    let(:client) { OpenAI::Client.new }

    it "creates a span and sets gen_ai request attributes" do
      client.chat(parameters: { model: "gpt-4o", messages: [{ role: "user", content: "Hi" }] })

      expect(span).to have_received(:set_attribute).with("gen_ai.operation.name", "chat")
      expect(span).to have_received(:set_attribute).with("gen_ai.system", "openai")
      expect(span).to have_received(:set_attribute).with("gen_ai.request.model", "gpt-4o")
    end

    it "sets response attributes from the result" do
      client.chat(parameters: { model: "gpt-4o" })

      expect(span).to have_received(:set_attribute).with("gen_ai.response.model", "gpt-4o-2024-05-13")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.id", "chatcmpl-abc123")
      expect(span).to have_received(:set_attribute).with("gen_ai.response.finish_reasons", ["stop"])
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 10)
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.output_tokens", 20)
    end

    it "finishes the span after response" do
      client.chat(parameters: { model: "gpt-4o" })
      expect(span).to have_received(:finish)
    end

    it "sets optional max_tokens, temperature, top_p" do
      client.chat(parameters: { model: "gpt-4o", max_tokens: 100, temperature: 0.7, top_p: 0.9 })

      expect(span).to have_received(:set_attribute).with("gen_ai.request.max_tokens", 100)
      expect(span).to have_received(:set_attribute).with("gen_ai.request.temperature", 0.7)
      expect(span).to have_received(:set_attribute).with("gen_ai.request.top_p", 0.9)
    end

    context "with tool calls in response" do
      before do
        OpenAI::Client.mock_response = {
          "id" => "chatcmpl-tool1",
          "model" => "gpt-4o",
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => nil,
                "tool_calls" => [
                  {
                    "id" => "call_abc123",
                    "function" => { "name" => "get_weather", "arguments" => '{"city":"SF"}' }
                  }
                ]
              },
              "finish_reason" => "tool_calls"
            }
          ],
          "usage" => { "prompt_tokens" => 15, "completion_tokens" => 25 }
        }
      end

      it "records tool calls as span events" do
        client.chat(parameters: { model: "gpt-4o" })

        expect(span).to have_received(:add_event).with("gen_ai.tool.call", attributes: {
          "gen_ai.tool.name" => "get_weather",
          "gen_ai.tool.call.id" => "call_abc123",
          "gen_ai.tool.call.arguments" => '{"city":"SF"}'
        })
      end
    end

    context "when capture_content is enabled" do
      before { ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "true" }
      after { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

      it "captures input messages on span" do
        client.chat(parameters: {
          model: "gpt-4o",
          messages: [
            { role: "user", content: "Hello" }
          ]
        })

        expect(span).to have_received(:set_attribute).with("gen_ai.input.messages", anything)
      end

      it "captures output messages on span" do
        client.chat(parameters: { model: "gpt-4o" })

        expect(span).to have_received(:set_attribute).with("gen_ai.output.messages", anything)
      end

      it "captures system instructions separately" do
        client.chat(parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: "You are a helper" },
            { role: "user", content: "Hi" }
          ]
        })

        expect(span).to have_received(:set_attribute).with("gen_ai.system_instructions", anything)
        expect(span).to have_received(:set_attribute).with("gen_ai.input.messages", anything)
      end
    end

    context "when capture_content is disabled" do
      before { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

      it "does not capture input or output messages" do
        client.chat(parameters: {
          model: "gpt-4o",
          messages: [{ role: "user", content: "Hello" }]
        })

        expect(span).not_to have_received(:set_attribute).with("gen_ai.input.messages", anything)
        expect(span).not_to have_received(:set_attribute).with("gen_ai.output.messages", anything)
      end
    end

    context "on error" do
      before do
        # Use a proc that raises - the mock_response will be called in the original method
        # but the prepend calls super which calls original chat.
        # We need super to raise. Override at the original method level.
        OpenAI::Client.define_method(:default_response) do
          raise StandardError, "API error"
        end
      end

      after do
        # Restore default behavior
        OpenAI::Client.define_method(:default_response) do
          {
            "id" => "chatcmpl-abc123",
            "model" => "gpt-4o-2024-05-13",
            "choices" => [
              {
                "message" => { "role" => "assistant", "content" => "Hello!" },
                "finish_reason" => "stop"
              }
            ],
            "usage" => { "prompt_tokens" => 10, "completion_tokens" => 20 }
          }
        end
      end

      it "sets error attributes and re-raises" do
        status_error = double("Status::Error")
        allow(OpenTelemetry::Trace::Status).to receive(:error).and_return(status_error)

        expect { client.chat(parameters: { model: "gpt-4o" }) }.to raise_error(StandardError, "API error")
        expect(span).to have_received(:set_attribute).with("error.type", "StandardError")
        expect(span).to have_received(:status=).with(status_error)
        expect(span).to have_received(:record_exception)
        expect(span).to have_received(:finish)
      end
    end
  end

  context "streaming chat" do
    let(:client) { OpenAI::Client.new }

    let(:standard_chunks) do
      [
        { "id" => "chatcmpl-s1", "model" => "gpt-4o", "choices" => [{ "delta" => { "content" => "Hel" }, "finish_reason" => nil }] },
        { "id" => "chatcmpl-s1", "model" => "gpt-4o", "choices" => [{ "delta" => { "content" => "lo!" }, "finish_reason" => "stop" }] },
        { "id" => "chatcmpl-s1", "model" => "gpt-4o", "choices" => [], "usage" => { "prompt_tokens" => 5, "completion_tokens" => 10 } }
      ]
    end

    before do
      # For streaming, mock_response returns an enumerator
      OpenAI::Client.mock_response = standard_chunks.each
    end

    it "returns a StreamWrapper that wraps the enumerator" do
      result = client.chat(parameters: { model: "gpt-4o", stream: true })
      expect(result).to be_a(Tracekit::LLM::OpenAIInstrumentation::StreamWrapper)
    end

    it "finalizes span with accumulated token counts after consuming stream" do
      result = client.chat(parameters: { model: "gpt-4o", stream: true })
      result.each { |_chunk| } # consume

      expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 5)
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.output_tokens", 10)
      expect(span).to have_received(:set_attribute).with("gen_ai.response.finish_reasons", ["stop"])
      expect(span).to have_received(:finish)
    end

    it "injects stream_options include_usage if not set" do
      result = client.chat(parameters: { model: "gpt-4o", stream: true })
      result.each { |_| }
      expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 5)
    end

    context "with tool call deltas" do
      let(:tool_chunks) do
        [
          {
            "id" => "chatcmpl-tc1", "model" => "gpt-4o",
            "choices" => [{ "delta" => { "tool_calls" => [{ "index" => 0, "id" => "call_1", "function" => { "name" => "get_weather", "arguments" => '{"ci' } }] }, "finish_reason" => nil }]
          },
          {
            "id" => "chatcmpl-tc1", "model" => "gpt-4o",
            "choices" => [{ "delta" => { "tool_calls" => [{ "index" => 0, "function" => { "arguments" => 'ty":"SF"}' } }] }, "finish_reason" => "tool_calls" }]
          },
          { "id" => "chatcmpl-tc1", "model" => "gpt-4o", "choices" => [], "usage" => { "prompt_tokens" => 8, "completion_tokens" => 12 } }
        ]
      end

      before do
        OpenAI::Client.mock_response = tool_chunks.each
      end

      it "accumulates tool call deltas and records as events on finalize" do
        result = client.chat(parameters: { model: "gpt-4o", stream: true })
        result.each { |_| }

        expect(span).to have_received(:add_event).with("gen_ai.tool.call", attributes: {
          "gen_ai.tool.name" => "get_weather",
          "gen_ai.tool.call.id" => "call_1",
          "gen_ai.tool.call.arguments" => '{"city":"SF"}'
        })
      end
    end

    context "when capture_content is enabled" do
      before do
        ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "true"
        OpenAI::Client.mock_response = standard_chunks.each
      end
      after { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

      it "accumulates content deltas and sets on span at end" do
        result = client.chat(parameters: { model: "gpt-4o", stream: true })
        result.each { |_| }

        expect(span).to have_received(:set_attribute).with("gen_ai.output.messages", anything)
      end
    end

    context "on stream error" do
      before do
        error_enum = Enumerator.new do |y|
          y << { "id" => "chatcmpl-err", "model" => "gpt-4o", "choices" => [{ "delta" => { "content" => "Hi" } }] }
          raise StandardError, "Stream error"
        end
        OpenAI::Client.mock_response = error_enum
      end

      it "sets error attributes and re-raises on stream error" do
        status_error = double("Status::Error")
        allow(OpenTelemetry::Trace::Status).to receive(:error).and_return(status_error)

        result = client.chat(parameters: { model: "gpt-4o", stream: true })
        expect { result.each { |_| } }.to raise_error(StandardError, "Stream error")
        expect(span).to have_received(:set_attribute).with("error.type", "StandardError")
        expect(span).to have_received(:finish)
      end
    end
  end
end
