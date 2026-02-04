# frozen_string_literal: true

require_relative "lib/tracekit/version"

Gem::Specification.new do |spec|
  spec.name = "tracekit"
  spec.version = Tracekit::VERSION
  spec.authors = ["TraceKit"]
  spec.email = ["support@tracekit.dev"]

  spec.summary = "TraceKit Ruby SDK - OpenTelemetry-based APM for Ruby applications"
  spec.description = "Complete APM solution with distributed tracing, metrics, code monitoring, and security scanning for Ruby and Rails applications"
  spec.homepage = "https://github.com/Tracekit-Dev/ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Tracekit-Dev/ruby-sdk"
  spec.metadata["changelog_uri"] = "https://github.com/Tracekit-Dev/ruby-sdk/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("{lib}/**/*") + %w[README.md LICENSE CHANGELOG.md]
  spec.bindir = "exe"
  spec.executables = []
  spec.require_paths = ["lib"]

  # OpenTelemetry dependencies
  spec.add_dependency "opentelemetry-sdk", "~> 1.2"
  spec.add_dependency "opentelemetry-exporter-otlp", "~> 0.26"
  spec.add_dependency "opentelemetry-instrumentation-http", "~> 0.23"
  spec.add_dependency "opentelemetry-instrumentation-net_http", "~> 0.22"

  # Core dependencies
  spec.add_dependency "concurrent-ruby", "~> 1.2"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
end
