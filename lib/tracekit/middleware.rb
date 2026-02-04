# frozen_string_literal: true

module Tracekit
  # Rack middleware for automatic TraceKit instrumentation of HTTP requests
  # Creates server spans with kind: :server for all incoming HTTP requests
  class Middleware
    def initialize(app)
      @app = app
      @tracer = OpenTelemetry.tracer_provider.tracer('tracekit-ruby', Tracekit::VERSION)
    end

    def call(env)
      sdk = SDK.current
      return @app.call(env) unless sdk

      request = Rack::Request.new(env)
      path = request.path
      method = request.request_method

      # Create server span for incoming HTTP request
      @tracer.in_span(
        span_name(request),
        attributes: span_attributes(request),
        kind: :server
      ) do |span|
        # Track metrics
        request_counter = sdk.counter("http.server.requests", {
          "http.method" => method,
          "http.route" => path
        })

        active_gauge = sdk.gauge("http.server.active_requests", {
          "http.method" => method
        })

        duration_histogram = sdk.histogram("http.server.request.duration", {
          "unit" => "ms"
        })

        active_gauge.inc
        start_time = Time.now

        # Add client IP to span
        if client_ip = extract_client_ip(request)
          span.set_attribute("http.client_ip", client_ip)
        end

        begin
          status, headers, body = @app.call(env)

          # Set response attributes
          span.set_attribute("http.status_code", status)

          # Set span status based on HTTP status code
          if status >= 500
            span.status = OpenTelemetry::Trace::Status.error("HTTP #{status}")
          elsif status >= 400
            span.status = OpenTelemetry::Trace::Status.error("HTTP #{status}")
          else
            span.status = OpenTelemetry::Trace::Status.ok
          end

          # Record successful request
          request_counter.inc

          # Record errors
          if status >= 400
            error_counter = sdk.counter("http.server.errors", {
              "http.method" => method,
              "http.status_code" => status.to_s
            })
            error_counter.inc
          end

          [status, headers, body]
        rescue => e
          # Record exception on span
          span.record_exception(e)
          span.status = OpenTelemetry::Trace::Status.error("Exception: #{e.class.name}")

          # Record exception metric
          error_counter = sdk.counter("http.server.errors", {
            "http.method" => method,
            "error.type" => e.class.name
          })
          error_counter.inc

          raise
        ensure
          active_gauge.dec
          duration = ((Time.now - start_time) * 1000).round(2)
          duration_histogram.record(duration)
        end
      end
    end

    private

    def span_name(request)
      # Use route if available (Rails), otherwise method + path
      route = request.env['action_dispatch.request.path_parameters']&.[](:controller)
      if route
        action = request.env['action_dispatch.request.path_parameters']&.[](:action)
        "#{request.request_method} #{route}##{action}"
      else
        "#{request.request_method} #{request.path}"
      end
    end

    def span_attributes(request)
      {
        'http.method' => request.request_method,
        'http.url' => request.url,
        'http.target' => request.path,
        'http.host' => request.host,
        'http.scheme' => request.scheme,
        'http.user_agent' => request.user_agent,
        'net.host.name' => request.host,
        'net.host.port' => request.port
      }.compact
    end

    def extract_client_ip(request)
      # Try X-Forwarded-For first
      forwarded = request.env["HTTP_X_FORWARDED_FOR"]
      return forwarded.split(",").first.strip if forwarded

      # Try X-Real-IP
      real_ip = request.env["HTTP_X_REAL_IP"]
      return real_ip if real_ip

      # Fall back to remote IP
      request.ip
    end
  end
end
