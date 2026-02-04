# frozen_string_literal: true

require "net/http"
require "json"

module Tracekit
  module Metrics
    # Exports metrics to TraceKit in OTLP (OpenTelemetry Protocol) format
    class Exporter
      def initialize(endpoint, api_key, service_name)
        @endpoint = endpoint
        @api_key = api_key
        @service_name = service_name
      end

      # Exports a batch of metric data points
      def export(data_points)
        return if data_points.empty?

        payload = to_otlp(data_points)

        uri = URI(@endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "X-API-Key" => @api_key,
          "User-Agent" => "tracekit-ruby-sdk/#{Tracekit::VERSION}"
        })
        request.body = JSON.generate(payload)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          warn "Metrics export failed: HTTP #{response.code}"
        end
      rescue => e
        warn "Metrics export error: #{e.message}"
      end

      private

      # Converts data points to OTLP format
      def to_otlp(data_points)
        # Group by name and type
        grouped = data_points.group_by { |dp| "#{dp.name}:#{dp.type}" }

        metrics = grouped.map do |key, points|
          name, type = key.split(":")

          otlp_data_points = points.map do |dp|
            {
              attributes: dp.tags.map { |k, v| { key: k, value: { stringValue: v.to_s } } },
              timeUnixNano: dp.timestamp_nanos.to_s,
              asDouble: dp.value.to_f
            }
          end

          if type == "counter"
            {
              name: name,
              sum: {
                dataPoints: otlp_data_points,
                aggregationTemporality: 2, # DELTA
                isMonotonic: true
              }
            }
          else # gauge or histogram
            {
              name: name,
              gauge: {
                dataPoints: otlp_data_points
              }
            }
          end
        end

        {
          resourceMetrics: [
            {
              resource: {
                attributes: [
                  { key: "service.name", value: { stringValue: @service_name } }
                ]
              },
              scopeMetrics: [
                {
                  scope: { name: "tracekit" },
                  metrics: metrics
                }
              ]
            }
          ]
        }
      end
    end
  end
end
