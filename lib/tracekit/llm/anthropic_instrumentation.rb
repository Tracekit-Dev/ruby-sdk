# frozen_string_literal: true

require_relative "common"

module Tracekit
  module LLM
    module AnthropicInstrumentation
      module_function

      def install(tracer)
        begin
          require "anthropic"
        rescue LoadError
          # anthropic gem not available, check if it's already defined (e.g. in tests)
          return false unless defined?(::Anthropic::Client)
        end

        return false unless defined?(::Anthropic::Client)

        instrumentation_mod = Module.new do
          define_method(:messages) do |**params|
            # When called with no parameters, return the Messages::Client (for batches etc.)
            return super(**params) unless params[:parameters]

            parameters = params[:parameters]
            model = parameters[:model] || parameters["model"] || "unknown"
            stream_proc = parameters[:stream] || parameters["stream"]
            is_streaming = stream_proc.is_a?(Proc)
            capture = Common.capture_content?

            span = tracer.start_span("chat #{model}", kind: :client)

            begin
              Common.set_request_attributes(span,
                provider: "anthropic",
                model: model,
                max_tokens: parameters[:max_tokens] || parameters["max_tokens"],
                temperature: parameters[:temperature] || parameters["temperature"],
                top_p: parameters[:top_p] || parameters["top_p"]
              )

              # Capture input content
              if capture
                system_prompt = parameters[:system] || parameters["system"]
                Common.capture_system_instructions(span, system_prompt) if system_prompt
                messages = parameters[:messages] || parameters["messages"]
                Common.capture_input_messages(span, messages) if messages
              end

              if is_streaming
                # Wrap the user's stream proc to accumulate span data
                accumulator = AnthropicStreamAccumulator.new(span, capture)
                wrapper_proc = proc do |event|
                  accumulator.process_event(event)
                  stream_proc.call(event)
                end

                # Replace stream proc with our wrapper
                wrapped_params = parameters.merge(stream: wrapper_proc)
                result = super(parameters: wrapped_params)
                accumulator.finalize
                result
              else
                result = super(**params)
                handle_anthropic_response(span, result, capture)
                result
              end
            rescue => e
              Common.set_error_attributes(span, e)
              span.finish
              raise
            end
          end

          private

          def handle_anthropic_response(span, result, capture)
            # Anthropic response: { id, type, role, content, model, stop_reason, usage }
            content_blocks = result["content"] || result[:content] || []
            usage = result["usage"] || result[:usage] || {}

            Common.set_response_attributes(span,
              model: result["model"] || result[:model],
              id: result["id"] || result[:id],
              finish_reasons: [(result["stop_reason"] || result[:stop_reason])].compact,
              input_tokens: usage["input_tokens"] || usage[:input_tokens],
              output_tokens: usage["output_tokens"] || usage[:output_tokens]
            )

            # Cache tokens (Anthropic-specific)
            cache_creation = usage["cache_creation_input_tokens"] || usage[:cache_creation_input_tokens]
            cache_read = usage["cache_read_input_tokens"] || usage[:cache_read_input_tokens]
            span.set_attribute("gen_ai.usage.cache_creation.input_tokens", cache_creation) if cache_creation
            span.set_attribute("gen_ai.usage.cache_read.input_tokens", cache_read) if cache_read

            # Tool calls from content blocks
            content_blocks.each do |block|
              block_type = block["type"] || block[:type]
              if block_type == "tool_use"
                input_val = block["input"] || block[:input]
                args = input_val.is_a?(String) ? input_val : JSON.generate(input_val)
                Common.record_tool_call(span,
                  name: block["name"] || block[:name] || "unknown",
                  id: block["id"] || block[:id],
                  arguments: args
                )
              end
            end

            # Output content capture
            if capture && content_blocks.any?
              Common.capture_output_messages(span, content_blocks)
            end
          rescue => _e
            # Never break user code
          ensure
            span.finish
          end
        end

        ::Anthropic::Client.prepend(instrumentation_mod)
        true
      end

      # Accumulates streaming event data for span attributes
      class AnthropicStreamAccumulator
        def initialize(span, capture_content)
          @span = span
          @capture = capture_content
          @model = nil
          @id = nil
          @stop_reason = nil
          @input_tokens = nil
          @output_tokens = nil
          @cache_creation_tokens = nil
          @cache_read_tokens = nil
          @output_chunks = []
          @tool_calls = {}
          @current_block_index = 0
        end

        def process_event(event)
          event_type = event["type"] || event[:type]

          case event_type
          when "message_start"
            message = event["message"] || event[:message] || {}
            @model = message["model"] || message[:model]
            @id = message["id"] || message[:id]
            usage = message["usage"] || message[:usage] || {}
            @input_tokens = usage["input_tokens"] || usage[:input_tokens]
            @cache_creation_tokens = usage["cache_creation_input_tokens"] || usage[:cache_creation_input_tokens]
            @cache_read_tokens = usage["cache_read_input_tokens"] || usage[:cache_read_input_tokens]

          when "content_block_start"
            @current_block_index = event["index"] || event[:index] || @current_block_index
            cb = event["content_block"] || event[:content_block] || {}
            if (cb["type"] || cb[:type]) == "tool_use"
              @tool_calls[@current_block_index] = {
                name: cb["name"] || cb[:name] || "unknown",
                id: cb["id"] || cb[:id],
                arguments: ""
              }
            end

          when "content_block_delta"
            delta = event["delta"] || event[:delta] || {}
            delta_type = delta["type"] || delta[:type]
            if delta_type == "text_delta" && @capture
              text = delta["text"] || delta[:text]
              @output_chunks << text if text
            elsif delta_type == "input_json_delta"
              partial = delta["partial_json"] || delta[:partial_json]
              idx = event["index"] || event[:index] || @current_block_index
              if partial && @tool_calls[idx]
                @tool_calls[idx][:arguments] += partial
              end
            end

          when "message_delta"
            delta = event["delta"] || event[:delta] || {}
            @stop_reason = delta["stop_reason"] || delta[:stop_reason] if delta["stop_reason"] || delta[:stop_reason]
            usage = event["usage"] || event[:usage] || {}
            @output_tokens = usage["output_tokens"] || usage[:output_tokens] if usage["output_tokens"] || usage[:output_tokens]
          end
        rescue => _e
          # Never fail on event processing
        end

        def finalize
          Common.set_response_attributes(@span,
            model: @model,
            id: @id,
            finish_reasons: @stop_reason ? [@stop_reason] : nil,
            input_tokens: @input_tokens,
            output_tokens: @output_tokens
          )

          @span.set_attribute("gen_ai.usage.cache_creation.input_tokens", @cache_creation_tokens) if @cache_creation_tokens
          @span.set_attribute("gen_ai.usage.cache_read.input_tokens", @cache_read_tokens) if @cache_read_tokens

          @tool_calls.each_value do |tc|
            Common.record_tool_call(@span, **tc)
          end

          if @capture && @output_chunks.any?
            full_content = @output_chunks.join
            Common.capture_output_messages(@span, [{ "type" => "text", "text" => full_content }])
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
