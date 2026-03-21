# frozen_string_literal: true

require "json"

module Tracekit
  module LLM
    module Common
      # Pattern-based PII regexes (all replaced with plain [REDACTED])
      SENSITIVE_KEY_PATTERN = /\A(password|passwd|pwd|secret|token|key|credential|api_key|apikey)\z/i
      EMAIL_PATTERN = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/
      SSN_PATTERN = /\b\d{3}-\d{2}-\d{4}\b/
      CREDIT_CARD_PATTERN = /\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b/
      AWS_KEY_PATTERN = /\bAKIA[0-9A-Z]{16}\b/
      BEARER_PATTERN = /Bearer\s+[A-Za-z0-9\-._~+\/]+=*/
      STRIPE_PATTERN = /\bsk_live_[a-zA-Z0-9]+/
      JWT_PATTERN = /\beyJ[A-Za-z0-9\-_]+\.eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+/
      PRIVATE_KEY_PATTERN = /-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----/

      CONTENT_PATTERNS = [
        EMAIL_PATTERN, SSN_PATTERN, CREDIT_CARD_PATTERN, AWS_KEY_PATTERN,
        BEARER_PATTERN, STRIPE_PATTERN, JWT_PATTERN, PRIVATE_KEY_PATTERN
      ].freeze

      module_function

      def scrub_pii(content)
        # Try JSON key-based scrubbing first
        begin
          parsed = JSON.parse(content)
          scrubbed = scrub_object(parsed)
          return JSON.generate(scrubbed)
        rescue JSON::ParserError
          # Not JSON, fall through to pattern scrubbing
        end
        scrub_patterns(content)
      end

      def scrub_patterns(str)
        result = str.dup
        CONTENT_PATTERNS.each { |pat| result.gsub!(pat, "[REDACTED]") }
        result
      end

      def scrub_object(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            if SENSITIVE_KEY_PATTERN.match?(k.to_s)
              h[k] = "[REDACTED]"
            else
              h[k] = scrub_object(v)
            end
          end
        when Array
          obj.map { |item| scrub_object(item) }
        when String
          scrub_patterns(obj)
        else
          obj
        end
      end

      def capture_content?
        env_val = ENV["TRACEKIT_LLM_CAPTURE_CONTENT"]
        return env_val.downcase == "true" || env_val == "1" if env_val
        false
      end

      def set_request_attributes(span, provider:, model:, max_tokens: nil, temperature: nil, top_p: nil)
        span.set_attribute("gen_ai.operation.name", "chat")
        span.set_attribute("gen_ai.system", provider)
        span.set_attribute("gen_ai.request.model", model)
        span.set_attribute("gen_ai.request.max_tokens", max_tokens) if max_tokens
        span.set_attribute("gen_ai.request.temperature", temperature) if temperature
        span.set_attribute("gen_ai.request.top_p", top_p) if top_p
      end

      def set_response_attributes(span, model: nil, id: nil, finish_reasons: nil, input_tokens: nil, output_tokens: nil)
        span.set_attribute("gen_ai.response.model", model) if model
        span.set_attribute("gen_ai.response.id", id) if id
        span.set_attribute("gen_ai.response.finish_reasons", finish_reasons) if finish_reasons&.any?
        span.set_attribute("gen_ai.usage.input_tokens", input_tokens) if input_tokens
        span.set_attribute("gen_ai.usage.output_tokens", output_tokens) if output_tokens
      end

      def set_error_attributes(span, error)
        span.set_attribute("error.type", error.class.name)
        span.status = OpenTelemetry::Trace::Status.error(error.message)
        span.record_exception(error)
      end

      def record_tool_call(span, name:, id: nil, arguments: nil)
        attrs = { "gen_ai.tool.name" => name }
        attrs["gen_ai.tool.call.id"] = id if id
        attrs["gen_ai.tool.call.arguments"] = arguments if arguments
        span.add_event("gen_ai.tool.call", attributes: attrs)
      end

      def capture_input_messages(span, messages)
        return unless messages
        serialized = JSON.generate(messages)
        span.set_attribute("gen_ai.input.messages", scrub_pii(serialized))
      end

      def capture_output_messages(span, content)
        return unless content
        serialized = JSON.generate(content)
        span.set_attribute("gen_ai.output.messages", scrub_pii(serialized))
      end

      def capture_system_instructions(span, system)
        return unless system
        serialized = system.is_a?(String) ? system : JSON.generate(system)
        span.set_attribute("gen_ai.system_instructions", scrub_pii(serialized))
      end
    end
  end
end
