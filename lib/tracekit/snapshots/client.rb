# frozen_string_literal: true

require "net/http"
require "json"
require "concurrent/hash"
require "concurrent/timer_task"

module Tracekit
  module Snapshots
    # Client for code monitoring - polls breakpoints and captures snapshots
    class Client
      def initialize(api_key, base_url, service_name, poll_interval_seconds = 30)
        @api_key = api_key
        @base_url = base_url
        @service_name = service_name
        @security_detector = Security::Detector.new
        @breakpoints_cache = Concurrent::Hash.new
        @registration_cache = Concurrent::Hash.new

        # Start polling timer
        @poll_task = Concurrent::TimerTask.new(execution_interval: poll_interval_seconds) do
          fetch_active_breakpoints
        end
        @poll_task.execute

        # Initial fetch
        fetch_active_breakpoints
      end

      # Captures a snapshot at the caller's location
      def capture_snapshot(label, variables, caller_location = nil)
        # Extract caller information
        caller_location ||= caller_locations(1, 1).first
        file_path = caller_location.path
        line_number = caller_location.lineno
        function_name = caller_location.label

        # Auto-register breakpoint
        auto_register_breakpoint(file_path, line_number, function_name, label)

        # Check if breakpoint is active
        location_key = "#{function_name}:#{label}"
        breakpoint = @breakpoints_cache[location_key] || @breakpoints_cache["#{file_path}:#{line_number}"]

        return unless breakpoint
        return unless breakpoint.enabled
        return if breakpoint.expire_at && Time.now > breakpoint.expire_at
        return if breakpoint.max_captures > 0 && breakpoint.capture_count >= breakpoint.max_captures

        # Scan for security issues
        scan_result = @security_detector.scan(variables)

        # Get trace context from OpenTelemetry
        trace_id = nil
        span_id = nil
        if defined?(OpenTelemetry::Trace)
          span = OpenTelemetry::Trace.current_span
          if span && span.context.valid?
            trace_id = span.context.hex_trace_id
            span_id = span.context.hex_span_id
          end
        end

        # Get stack trace
        stack_trace = caller.join("\n")

        snapshot = Snapshot.new(
          breakpoint_id: breakpoint.id,
          service_name: @service_name,
          file_path: file_path,
          function_name: function_name,
          label: label,
          line_number: line_number,
          variables: scan_result.sanitized_variables,
          security_flags: scan_result.security_flags.map(&:to_h),
          stack_trace: stack_trace,
          trace_id: trace_id,
          span_id: span_id,
          captured_at: Time.now.utc.iso8601
        )

        # Submit asynchronously
        Thread.new { submit_snapshot(snapshot) }
      end

      # Shuts down the client
      def shutdown
        @poll_task&.shutdown
      end

      private

      def fetch_active_breakpoints
        url = "#{@base_url}/sdk/snapshots/active/#{@service_name}"
        uri = URI(url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri.path)
        request["X-API-Key"] = @api_key

        response = http.request(request)
        return unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body, symbolize_names: true)
        update_breakpoint_cache(data[:breakpoints]) if data[:breakpoints]
      rescue => e
        # Silently ignore errors fetching breakpoints
        warn "Error fetching breakpoints: #{e.message}" if ENV["DEBUG"]
      end

      def update_breakpoint_cache(breakpoints)
        @breakpoints_cache.clear

        breakpoints.each do |bp_data|
          bp = BreakpointConfig.new(
            id: bp_data[:id],
            file_path: bp_data[:file_path],
            line_number: bp_data[:line_number],
            function_name: bp_data[:function_name],
            label: bp_data[:label],
            enabled: bp_data[:enabled],
            max_captures: bp_data[:max_captures] || 0,
            capture_count: bp_data[:capture_count] || 0,
            expire_at: bp_data[:expire_at] ? Time.parse(bp_data[:expire_at]) : nil
          )

          # Key by function + label
          if bp.label && bp.function_name
            label_key = "#{bp.function_name}:#{bp.label}"
            @breakpoints_cache[label_key] = bp
          end

          # Key by file + line
          line_key = "#{bp.file_path}:#{bp.line_number}"
          @breakpoints_cache[line_key] = bp
        end
      end

      def auto_register_breakpoint(file_path, line_number, function_name, label)
        reg_key = "#{function_name}:#{label}"
        return if @registration_cache[reg_key]

        @registration_cache[reg_key] = true

        Thread.new do
          begin
            registration = {
              service_name: @service_name,
              file_path: file_path,
              line_number: line_number,
              function_name: function_name,
              label: label
            }

            uri = URI("#{@base_url}/sdk/snapshots/auto-register")
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"
            http.read_timeout = 10

            request = Net::HTTP::Post.new(uri.path, {
              "Content-Type" => "application/json",
              "X-API-Key" => @api_key
            })
            request.body = JSON.generate(registration)

            response = http.request(request)

            # Refresh breakpoints cache after successful registration
            if response.is_a?(Net::HTTPSuccess)
              sleep 0.5 # Small delay for backend processing
              fetch_active_breakpoints
            end
          rescue => e
            # Silently ignore auto-registration errors
            warn "Error auto-registering breakpoint: #{e.message}" if ENV["DEBUG"]
          end
        end
      end

      def submit_snapshot(snapshot)
        uri = URI("#{@base_url}/sdk/snapshots/capture")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "X-API-Key" => @api_key
        })
        request.body = JSON.generate(snapshot.to_h)

        http.request(request)
      rescue => e
        # Silently ignore snapshot submission errors
        warn "Error submitting snapshot: #{e.message}" if ENV["DEBUG"]
      end
    end
  end
end
