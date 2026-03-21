# frozen_string_literal: true

module Api
  class LlmController < ActionController::API
    def show
      results = {}
      passed = 0
      failed = 0
      skipped = 0

      # OpenAI tests
      openai_key = ENV["OPENAI_API_KEY"]
      if openai_key.present? && openai_key != "your_openai_key_here"
        # Non-streaming
        begin
          client = OpenAI::Client.new(access_token: openai_key)
          response = client.chat(parameters: {
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: "Say hello in exactly 3 words." }],
            max_tokens: 50
          })
          content = response.dig("choices", 0, "message", "content")
          results["openai_non_streaming"] = {
            status: "PASS",
            model: response["model"],
            content: content,
            streaming: false
          }
          passed += 1
        rescue => e
          results["openai_non_streaming"] = { status: "FAIL", error: e.message }
          failed += 1
        end

        # Streaming
        begin
          client = OpenAI::Client.new(access_token: openai_key)
          chunks = []
          model_name = nil
          client.chat(parameters: {
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: "Say goodbye in exactly 3 words." }],
            max_tokens: 50,
            stream: proc { |chunk, _bytesize|
              model_name ||= chunk.dig("model")
              delta = chunk.dig("choices", 0, "delta", "content")
              chunks << delta if delta
            }
          })
          results["openai_streaming"] = {
            status: "PASS",
            model: model_name,
            content: chunks.join,
            streaming: true
          }
          passed += 1
        rescue => e
          results["openai_streaming"] = { status: "FAIL", error: e.message }
          failed += 1
        end
      else
        results["openai"] = "SKIPPED - OPENAI_API_KEY not set"
        skipped += 2
      end

      # Anthropic tests
      anthropic_key = ENV["ANTHROPIC_API_KEY"]
      if anthropic_key.present? && anthropic_key != "your_anthropic_key_here"
        # Non-streaming
        begin
          client = Anthropic::Client.new(api_key: anthropic_key)
          response = client.messages.create(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 50,
            messages: [{ role: "user", content: "Say hello in exactly 3 words." }]
          )
          content_blocks = response["content"] || []
          text = content_blocks.map { |b| b["text"] }.compact.join
          results["anthropic_non_streaming"] = {
            status: "PASS",
            model: response["model"],
            content: text,
            streaming: false
          }
          passed += 1
        rescue => e
          results["anthropic_non_streaming"] = { status: "FAIL", error: e.message }
          failed += 1
        end

        # Streaming
        begin
          client = Anthropic::Client.new(api_key: anthropic_key)
          stream_chunks = []
          stream_model = nil
          client.messages.create(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 50,
            messages: [{ role: "user", content: "Say goodbye in exactly 3 words." }],
            stream: proc { |event|
              event_type = event["type"]
              if event_type == "message_start"
                stream_model = event.dig("message", "model")
              elsif event_type == "content_block_delta"
                delta_text = event.dig("delta", "text")
                stream_chunks << delta_text if delta_text
              end
            }
          )
          results["anthropic_streaming"] = {
            status: "PASS",
            model: stream_model,
            content: stream_chunks.join,
            streaming: true
          }
          passed += 1
        rescue => e
          results["anthropic_streaming"] = { status: "FAIL", error: e.message }
          failed += 1
        end
      else
        results["anthropic"] = "SKIPPED - ANTHROPIC_API_KEY not set"
        skipped += 2
      end

      results["summary"] = { passed: passed, failed: failed, skipped: skipped }
      render json: results
    end
  end
end
