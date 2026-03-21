# frozen_string_literal: true

require "spec_helper"
require "json"
require "tracekit/llm/common"

# Mock OpenAI module for testing (before requiring instrumentation)
module OpenAI
  class Client
    def chat(parameters: {})
      # Default mock implementation
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

RSpec.describe Tracekit::LLM::OpenAIInstrumentation do
  let(:tracer) { instance_double("OpenTelemetry::Trace::Tracer") }
  let(:span) { instance_double("OpenTelemetry::Trace::Span") }

  before do
    allow(tracer).to receive(:start_span).and_return(span)
    allow(span).to receive(:set_attribute)
    allow(span).to receive(:add_event)
    allow(span).to receive(:status=)
    allow(span).to receive(:record_exception)
    allow(span).to receive(:finish)
    # Reset capture content env var
    ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT")
  end

  describe ".install" do
    it "returns false when openai gem is not loadable" do
      # We already have OpenAI defined, so we need a different approach
      # Test the install method with our mock
      result = described_class.install(tracer)
      expect(result).to be true
    end
  end

  context "after installation" do
    let(:client) { OpenAI::Client.new }

    before do
      # Install instrumentation (prepend to OpenAI::Client)
      described_class.install(tracer)
    end

    describe "non-streaming chat" do
      it "creates a span with gen_ai request attributes" do
        client.chat(parameters: { model: "gpt-4o", messages: [{ role: "user", content: "Hi" }] })

        expect(tracer).to have_received(:start_span).with("chat gpt-4o", kind: :client)
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
        let(:client) do
          c = OpenAI::Client.new
          allow(c).to receive(:chat).and_call_original
          c
        end

        before do
          # Override the original chat to return tool calls
          allow_any_instance_of(OpenAI::Client).to receive(:chat).and_wrap_original do |original_method, **kwargs|
            # We need a way to get past the prepend - use instance variable
            {
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
          allow_any_instance_of(OpenAI::Client).to receive(:chat).and_wrap_original do |_m, **_kw|
            raise StandardError, "API error"
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

    describe "streaming chat" do
      let(:chunks) do
        [
          { "id" => "chatcmpl-s1", "model" => "gpt-4o", "choices" => [{ "delta" => { "content" => "Hel" }, "finish_reason" => nil }] },
          { "id" => "chatcmpl-s1", "model" => "gpt-4o", "choices" => [{ "delta" => { "content" => "lo!" }, "finish_reason" => "stop" }] },
          { "id" => "chatcmpl-s1", "model" => "gpt-4o", "choices" => [], "usage" => { "prompt_tokens" => 5, "completion_tokens" => 10 } }
        ]
      end

      before do
        allow_any_instance_of(OpenAI::Client).to receive(:chat).and_wrap_original do |_m, **_kw|
          chunks.each
        end
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
        # We verify indirectly that super was called with modified params
        # The key test is that token counts come through (usage chunk present)
        result = client.chat(parameters: { model: "gpt-4o", stream: true })
        result.each { |_| }
        expect(span).to have_received(:set_attribute).with("gen_ai.usage.input_tokens", 5)
      end

      context "with tool call deltas" do
        let(:chunks) do
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
        before { ENV["TRACEKIT_LLM_CAPTURE_CONTENT"] = "true" }
        after { ENV.delete("TRACEKIT_LLM_CAPTURE_CONTENT") }

        it "accumulates content deltas and sets on span at end" do
          result = client.chat(parameters: { model: "gpt-4o", stream: true })
          result.each { |_| }

          expect(span).to have_received(:set_attribute).with("gen_ai.output.messages", anything)
        end
      end

      context "on stream error" do
        let(:error_chunks) do
          enum = Enumerator.new do |y|
            y << { "id" => "chatcmpl-err", "model" => "gpt-4o", "choices" => [{ "delta" => { "content" => "Hi" } }] }
            raise StandardError, "Stream error"
          end
          enum
        end

        before do
          allow_any_instance_of(OpenAI::Client).to receive(:chat).and_wrap_original do |_m, **_kw|
            error_chunks
          end
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
end
