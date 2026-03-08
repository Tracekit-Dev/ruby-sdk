# frozen_string_literal: true

require "net/http"
require "json"
require "concurrent/hash"
require "concurrent/timer_task"

module Tracekit
  module Snapshots
    # Client for code monitoring - polls breakpoints and captures snapshots
    class Client
      # Opt-in capture limits (all disabled by default: nil = unlimited)
      attr_accessor :capture_depth    # nil = unlimited depth (default)
      attr_accessor :max_payload      # nil = unlimited payload bytes (default)
      attr_accessor :capture_timeout  # nil = no timeout seconds (default)

      def initialize(api_key, base_url, service_name, poll_interval_seconds = 30, **opts)
        @api_key = api_key
        @base_url = base_url
        @service_name = service_name
        @security_detector = Security::Detector.new
        @breakpoints_cache = Concurrent::Hash.new
        @registration_cache = Concurrent::Hash.new

        # Opt-in capture limits
        @capture_depth = opts[:capture_depth]
        @max_payload = opts[:max_payload]
        @capture_timeout = opts[:capture_timeout]

        # Kill switch: server-initiated monitoring disable
        @kill_switch_active = false
        @normal_poll_interval = poll_interval_seconds

        # SSE (Server-Sent Events) real-time updates
        @sse_endpoint = nil
        @sse_active = false
        @sse_thread = nil

        # Circuit breaker state (Mutex-protected for thread safety)
        cb_config = opts[:circuit_breaker] || {}
        @cb_mutex = Mutex.new
        @cb_failure_timestamps = []
        @cb_state = "closed"
        @cb_opened_at = nil
        @cb_max_failures = cb_config[:max_failures] || 3
        @cb_window_seconds = cb_config[:window_seconds] || 60
        @cb_cooldown_seconds = cb_config[:cooldown_seconds] || 300
        @pending_events = []

        # Start polling timer
        @poll_task = Concurrent::TimerTask.new(execution_interval: poll_interval_seconds) do
          fetch_active_breakpoints
        end
        @poll_task.execute

        # Initial fetch
        fetch_active_breakpoints
      end

      # Captures a snapshot at the caller's location.
      # Crash isolation: rescues all exceptions so TraceKit never crashes the host app.
      def capture_snapshot(label, variables, caller_location = nil)
        begin
          do_capture_snapshot(label, variables, caller_location)
        rescue => e
          warn "TraceKit: error in capture_snapshot: #{e.message}" if ENV["DEBUG"]
        end
      end

      private

      def do_capture_snapshot(label, variables, caller_location)
        # Kill switch: skip all capture when server has disabled monitoring
        return if @kill_switch_active

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

        # Apply opt-in capture depth limit
        if @capture_depth && @capture_depth > 0
          variables = limit_depth(variables, 0)
        end

        # Scan for security issues
        scan_result = @security_detector.scan(variables)

        # Get trace context from OpenTelemetry
        trace_id = nil
        span_id = nil
        if defined?(OpenTelemetry::Trace)
          span = OpenTelemetry::Trace.current_span
          if span && span.context.valid? && (span.context.trace_flags & OpenTelemetry::Trace::TraceFlags::SAMPLED) != 0
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

        # Apply opt-in max payload limit
        serialized = JSON.generate(snapshot.to_h)
        if @max_payload && @max_payload > 0 && serialized.bytesize > @max_payload
          snapshot = Snapshot.new(
            breakpoint_id: breakpoint.id,
            service_name: @service_name,
            file_path: file_path,
            function_name: function_name,
            label: label,
            line_number: line_number,
            variables: { "_truncated" => true, "_payload_size" => serialized.bytesize, "_max_payload" => @max_payload },
            security_flags: [],
            stack_trace: stack_trace,
            trace_id: trace_id,
            span_id: span_id,
            captured_at: Time.now.utc.iso8601
          )
        end

        # Submit asynchronously (with optional timeout)
        if @capture_timeout && @capture_timeout > 0
          thread = Thread.new { submit_snapshot(snapshot) }
          unless thread.join(@capture_timeout)
            warn "TraceKit: capture timeout exceeded (#{@capture_timeout}s)" if ENV["DEBUG"]
            thread.kill
          end
        else
          Thread.new { submit_snapshot(snapshot) }
        end
      end

      public

      # Shuts down the client
      def shutdown
        @poll_task&.shutdown
        close_sse
      end

      private

      # Limit variable nesting depth (opt-in)
      def limit_depth(data, current_depth)
        return { "_truncated" => true, "_depth" => current_depth } if current_depth >= @capture_depth

        case data
        when Hash
          result = {}
          data.each do |k, v|
            result[k] = limit_depth(v, current_depth + 1)
          end
          result
        when Array
          data.map { |item| limit_depth(item, current_depth + 1) }
        else
          data
        end
      end

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

        # SSE auto-discovery: if polling response includes sse_endpoint, start SSE connection
        if data[:sse_endpoint] && !@sse_active
          @sse_endpoint = data[:sse_endpoint]
          start_sse_thread(@sse_endpoint)
        end

        # Handle kill switch state (missing field = false for backward compat)
        new_kill_state = data[:kill_switch] == true
        if new_kill_state && !@kill_switch_active
          warn "TraceKit: Code monitoring disabled by server kill switch. Polling at reduced frequency."
          reschedule_polling(60)
        elsif !new_kill_state && @kill_switch_active
          warn "TraceKit: Code monitoring re-enabled by server."
          reschedule_polling(@normal_poll_interval)
        end
        @kill_switch_active = new_kill_state
      rescue => e
        # Silently ignore errors fetching breakpoints
        warn "Error fetching breakpoints: #{e.message}" if ENV["DEBUG"]
      end

      def reschedule_polling(interval_seconds)
        @poll_task&.shutdown
        @poll_task = Concurrent::TimerTask.new(execution_interval: interval_seconds) do
          fetch_active_breakpoints
        end
        @poll_task.execute
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
        # Circuit breaker check
        return unless circuit_breaker_should_allow?

        uri = URI("#{@base_url}/sdk/snapshots/capture")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "X-API-Key" => @api_key
        })
        request.body = JSON.generate(snapshot.to_h)

        response = http.request(request)

        # Server error (5xx) -- count as circuit breaker failure
        if response.is_a?(Net::HTTPServerError)
          queue_circuit_breaker_event if circuit_breaker_record_failure
        end
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
        # Network/timeout error -- count as circuit breaker failure
        warn "Error submitting snapshot: #{e.message}" if ENV["DEBUG"]
        queue_circuit_breaker_event if circuit_breaker_record_failure
      rescue => e
        # Other errors -- do NOT count as circuit breaker failure
        warn "Error submitting snapshot: #{e.message}" if ENV["DEBUG"]
      end

      # Start SSE connection in a daemon thread
      def start_sse_thread(endpoint)
        close_sse # Close any existing SSE connection

        @sse_thread = Thread.new do
          begin
            connect_sse(endpoint)
          rescue => e
            warn "TraceKit: SSE thread error: #{e.message}" if ENV["DEBUG"]
            @sse_active = false
          end
        end
        @sse_thread.abort_on_exception = false
      end

      # Connect to the SSE endpoint for real-time breakpoint updates.
      # Falls back to polling if SSE connection fails or disconnects.
      # Crash isolation: all exceptions are rescued so TraceKit never crashes the host app.
      def connect_sse(endpoint)
        full_url = "#{@base_url}#{endpoint}"
        uri = URI(full_url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 0 # No timeout for SSE (long-lived connection)
        http.open_timeout = 10

        request = Net::HTTP::Get.new(uri.path)
        request["X-API-Key"] = @api_key
        request["Accept"] = "text/event-stream"
        request["Cache-Control"] = "no-cache"

        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            warn "TraceKit: SSE connection failed with HTTP #{response.code}, falling back to polling" if ENV["DEBUG"]
            @sse_active = false
            return
          end

          @sse_active = true
          warn "TraceKit: SSE connected to #{endpoint}" if ENV["DEBUG"]

          event_type = nil
          event_data = ""

          response.read_body do |chunk|
            chunk.each_line do |line|
              line = line.chomp

              if line.start_with?("event:")
                event_type = line.sub(/^event:\s*/, "").strip
              elsif line.start_with?("data:")
                event_data += line.sub(/^data:\s*/, "")
              elsif line.empty? && event_type
                # Empty line signals end of event -- process it
                handle_sse_event(event_type, event_data)
                event_type = nil
                event_data = ""
              end
            end
          end
        end

        # Connection closed cleanly
        @sse_active = false
        warn "TraceKit: SSE connection closed, falling back to polling" if ENV["DEBUG"]
      rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout,
             IOError, EOFError => e
        warn "TraceKit: SSE connection error: #{e.message}, falling back to polling" if ENV["DEBUG"]
        @sse_active = false
      rescue => e
        warn "TraceKit: SSE unexpected error: #{e.message}" if ENV["DEBUG"]
        @sse_active = false
      end

      # Handle a parsed SSE event
      def handle_sse_event(event_type, data_str)
        case event_type
        when "init"
          payload = JSON.parse(data_str, symbolize_names: true)
          update_breakpoint_cache(payload[:breakpoints]) if payload[:breakpoints]

          # Update kill switch from init event
          if payload.key?(:kill_switch)
            new_kill_state = payload[:kill_switch] == true
            if new_kill_state && !@kill_switch_active
              warn "TraceKit: Code monitoring disabled by server kill switch."
              close_sse
            end
            @kill_switch_active = new_kill_state
          end

        when "breakpoint_created", "breakpoint_updated"
          bp_data = JSON.parse(data_str, symbolize_names: true)
          upsert_breakpoint(bp_data)

        when "breakpoint_deleted"
          bp_data = JSON.parse(data_str, symbolize_names: true)
          remove_breakpoint(bp_data[:id])

        when "kill_switch"
          payload = JSON.parse(data_str, symbolize_names: true)
          @kill_switch_active = payload[:enabled] == true
          reschedule_polling(@kill_switch_active ? 60 : @normal_poll_interval)
          if @kill_switch_active
            warn "TraceKit: Code monitoring disabled by server kill switch via SSE."
            close_sse
          end

        when "heartbeat", "sdk_count"
          # No action needed -- heartbeat keeps connection alive, sdk_count is for dashboard UI

        else
          warn "TraceKit: Unknown SSE event type: #{event_type}" if ENV["DEBUG"]
        end
      rescue JSON::ParserError => e
        warn "TraceKit: SSE JSON parse error for '#{event_type}': #{e.message}" if ENV["DEBUG"]
      rescue => e
        warn "TraceKit: SSE event handling error: #{e.message}" if ENV["DEBUG"]
      end

      # Upsert a single breakpoint into the cache
      def upsert_breakpoint(bp_data)
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

      # Remove a breakpoint from the cache by ID
      def remove_breakpoint(breakpoint_id)
        return unless breakpoint_id

        @breakpoints_cache.delete_if { |_key, bp| bp.id == breakpoint_id }
      end

      # Close the active SSE connection
      def close_sse
        @sse_active = false
        if @sse_thread&.alive?
          @sse_thread.kill
          @sse_thread = nil
        end
      end

      def circuit_breaker_should_allow?
        @cb_mutex.synchronize do
          return true if @cb_state == "closed"

          # Check cooldown
          if @cb_opened_at && (Time.now.to_f - @cb_opened_at) >= @cb_cooldown_seconds
            @cb_state = "closed"
            @cb_failure_timestamps.clear
            @cb_opened_at = nil
            warn "TraceKit: Code monitoring resumed"
            return true
          end

          false
        end
      end

      def circuit_breaker_record_failure
        @cb_mutex.synchronize do
          now = Time.now.to_f
          @cb_failure_timestamps << now

          # Prune old timestamps
          cutoff = now - @cb_window_seconds
          @cb_failure_timestamps.reject! { |ts| ts <= cutoff }

          if @cb_failure_timestamps.size >= @cb_max_failures && @cb_state == "closed"
            @cb_state = "open"
            @cb_opened_at = now
            warn "TraceKit: Code monitoring paused (#{@cb_max_failures} capture failures in #{@cb_window_seconds}s). Auto-resumes in #{@cb_cooldown_seconds / 60} min."
            return true
          end

          false
        end
      end

      def queue_circuit_breaker_event
        @cb_mutex.synchronize do
          @pending_events << {
            type: "circuit_breaker_tripped",
            service_name: @service_name,
            failure_count: @cb_max_failures,
            window_seconds: @cb_window_seconds,
            cooldown_seconds: @cb_cooldown_seconds,
            timestamp: Time.now.utc.iso8601
          }
        end
      end
    end
  end
end
