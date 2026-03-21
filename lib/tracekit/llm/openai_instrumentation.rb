# frozen_string_literal: true

require_relative "common"

module Tracekit
  module LLM
    module OpenAIInstrumentation
      module_function

      def install(tracer)
        # Try to load the OpenAI gem
        begin
          require "openai"
        rescue LoadError
          # openai gem not available, check if it's already defined (e.g. in tests)
          return false unless defined?(::OpenAI::Client)
        end

        client_class = ::OpenAI::Client
        return false unless client_class

        # Create the prepend module dynamically with tracer closure
        instrumentation_mod = Module.new do
          define_method(:chat) do |parameters: {}|
            model = parameters[:model] || parameters["model"] || "unknown"
            is_streaming = !!(parameters[:stream] || parameters["stream"])
            capture = Common.capture_content?

            span = tracer.start_span("chat #{model}", kind: :client)

            begin
              Common.set_request_attributes(span,
                provider: "openai",
                model: model,
                max_tokens: parameters[:max_tokens] || parameters["max_tokens"] || parameters[:max_completion_tokens] || parameters["max_completion_tokens"],
                temperature: parameters[:temperature] || parameters["temperature"],
                top_p: parameters[:top_p] || parameters["top_p"]
              )

              # Capture input content
              if capture
                messages = parameters[:messages] || parameters["messages"]
                if messages
                  system_msgs = messages.select { |m| (m[:role] || m["role"]) == "system" }
                  non_system = messages.reject { |m| (m[:role] || m["role"]) == "system" }
                  Common.capture_system_instructions(span, system_msgs) if system_msgs.any?
                  Common.capture_input_messages(span, non_system)
                end
              end

              # For streaming, inject stream_options.include_usage
              if is_streaming
                params = parameters.dup
                so = params[:stream_options] || params["stream_options"] || {}
                unless so[:include_usage] || so["include_usage"]
                  params[:stream_options] = so.merge(include_usage: true)
                end
                result = super(parameters: params)
                return StreamWrapper.new(result, span, capture)
              end

              result = super(parameters: parameters)

              # Non-streaming response handling
              handle_response(span, result, capture)
              result
            rescue => e
              Common.set_error_attributes(span, e)
              span.finish
              raise
            end
          end

          private

          def handle_response(span, result, capture)
            choices = result.dig("choices") || []
            Common.set_response_attributes(span,
              model: result["model"],
              id: result["id"],
              finish_reasons: choices.map { |c| c["finish_reason"] }.compact,
              input_tokens: result.dig("usage", "prompt_tokens"),
              output_tokens: result.dig("usage", "completion_tokens")
            )

            # Tool calls
            choices.each do |choice|
              (choice.dig("message", "tool_calls") || []).each do |tc|
                Common.record_tool_call(span,
                  name: tc.dig("function", "name") || "unknown",
                  id: tc["id"],
                  arguments: tc.dig("function", "arguments")
                )
              end
            end

            # Output content capture
            if capture && choices.any?
              output_msgs = choices.map { |c| c["message"] }.compact
              Common.capture_output_messages(span, output_msgs) if output_msgs.any?
            end
          rescue => _e
            # Never break user code
          ensure
            span.finish
          end
        end

        client_class.prepend(instrumentation_mod)
        true
      end

      # Wraps OpenAI streaming response to accumulate tokens
      class StreamWrapper
        include Enumerable

        def initialize(enum, span, capture_content)
          @enum = enum
          @span = span
          @capture = capture_content
          @model = nil
          @id = nil
          @finish_reason = nil
          @input_tokens = nil
          @output_tokens = nil
          @output_chunks = []
          @tool_calls = {}
        end

        def each(&block)
          return enum_for(:each) unless block_given?

          @enum.each do |chunk|
            process_chunk(chunk)
            block.call(chunk)
          end
          finalize
        rescue => e
          Common.set_error_attributes(@span, e)
          @span.finish
          raise
        end

        private

        def process_chunk(chunk)
          @model ||= chunk.dig("model")
          @id ||= chunk.dig("id")

          if (usage = chunk["usage"])
            @input_tokens = usage["prompt_tokens"] if usage["prompt_tokens"]
            @output_tokens = usage["completion_tokens"] if usage["completion_tokens"]
          end

          (chunk["choices"] || []).each do |choice|
            @finish_reason = choice["finish_reason"] if choice["finish_reason"]
            delta = choice["delta"] || {}
            @output_chunks << delta["content"] if @capture && delta["content"]

            (delta["tool_calls"] || []).each do |tc|
              idx = tc["index"] || 0
              if @tool_calls[idx]
                @tool_calls[idx][:arguments] = (@tool_calls[idx][:arguments] || "") + (tc.dig("function", "arguments") || "")
              else
                @tool_calls[idx] = {
                  name: tc.dig("function", "name") || "unknown",
                  id: tc["id"],
                  arguments: tc.dig("function", "arguments") || ""
                }
              end
            end
          end
        rescue => _e
          # Never fail on chunk processing
        end

        def finalize
          Common.set_response_attributes(@span,
            model: @model,
            id: @id,
            finish_reasons: @finish_reason ? [@finish_reason] : nil,
            input_tokens: @input_tokens,
            output_tokens: @output_tokens
          )

          @tool_calls.each_value do |tc|
            Common.record_tool_call(@span, **tc)
          end

          if @capture && @output_chunks.any?
            full_content = @output_chunks.join
            Common.capture_output_messages(@span, [{ "role" => "assistant", "content" => full_content }])
          end
        rescue => _e
          # Never break user code
        ensure
          @span.finish
        end
      end
    end
  end
end
