# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-02-04

### Added

- Initial release of TraceKit Ruby SDK
- OpenTelemetry-based distributed tracing with W3C TraceContext propagation
- Metrics API with Counter, Gauge, and Histogram support
- Automatic metrics buffering (100 metrics or 10 seconds)
- OTLP/HTTP export for traces and metrics
- Code monitoring with snapshot capture and auto-registration
- Security scanning for PII and credentials with automatic redaction
- Local UI auto-detection for development workflows
- Rails integration via Railtie with automatic configuration
- Rack middleware for request instrumentation
- Thread-safe metrics collection using concurrent-ruby
- Comprehensive test suite with RSpec
- Cross-service test application (ruby-test) on port 5002
- Builder pattern configuration with fluent API
- Endpoint resolution logic matching SDK specification
- Graceful shutdown with resource cleanup
- Ruby 2.7+ support

### Features

#### Configuration
- Environment variable-based configuration for Rails
- Manual configuration for vanilla Ruby applications
- Configurable sampling rate (0.0 - 1.0)
- Configurable code monitoring poll interval
- SSL/TLS support with configurable endpoint

#### Distributed Tracing
- Automatic HTTP request/response tracing
- W3C TraceContext header propagation
- OpenTelemetry auto-instrumentation for common libraries
- Trace correlation with code monitoring snapshots

#### Metrics
- Counter: Monotonic increasing values
- Gauge: Point-in-time values with inc/dec/set operations
- Histogram: Value distribution recording
- Tag support for dimensional metrics
- Automatic buffering and batch export
- Thread-safe concurrent collection

#### Code Monitoring
- Non-breaking snapshot capture
- Automatic file/line/function context extraction
- Variable state capture with security scanning
- Breakpoint auto-registration
- Polling-based activation check (30-second interval)
- Trace correlation (trace_id, span_id)
- Zero performance impact when breakpoints inactive

#### Security
- PII detection: email, SSN, credit card, phone numbers
- Credential detection: API keys, AWS keys, Stripe keys, JWT, private keys, passwords
- Automatic redaction with security flags
- Variable-level scanning

#### Rails Integration
- Automatic Railtie configuration
- ENV-based configuration loading
- Automatic middleware insertion
- Graceful shutdown on Rails exit
- Zero-configuration setup

#### Rack Integration
- Request/response instrumentation
- Automatic metric tracking:
  - `http.server.requests` (counter)
  - `http.server.active_requests` (gauge)
  - `http.server.request.duration` (histogram)
- Client IP extraction from headers
- OpenTelemetry span enrichment

### Dependencies

- opentelemetry-sdk ~> 1.2
- opentelemetry-exporter-otlp ~> 0.26
- opentelemetry-instrumentation-all ~> 0.50
- concurrent-ruby ~> 1.2

### Test Application

- Rails 7 API-only application
- Standard test endpoints for cross-service communication
- HTTParty for HTTP client testing
- Port 5002 (as per SDK specification)
- Environment variable configuration
- Example usage of all SDK features

### Documentation

- Comprehensive README with quick start guide
- API documentation with code examples
- Configuration reference
- Test application setup guide
- MIT License

---

## Release Notes

### v0.1.0 - Initial Release

This is the first production-ready release of the TraceKit Ruby SDK. It provides complete feature parity with other TraceKit SDKs, including distributed tracing, metrics, and code monitoring.

**Key Highlights**:

1. **Rails-First Design**: Automatic configuration via Railtie makes Rails integration zero-configuration
2. **OpenTelemetry Native**: Built on industry-standard OpenTelemetry for maximum compatibility
3. **Thread-Safe**: Uses concurrent-ruby for safe metric collection in multi-threaded applications
4. **Security Built-In**: Automatic PII and credential detection prevents accidental data exposure
5. **Production-Ready**: Comprehensive error handling, graceful shutdown, and resource cleanup

**Tested With**:
- Ruby 2.7, 3.0, 3.1, 3.2, 3.3
- Rails 6.0, 6.1, 7.0, 7.1
- Sinatra 3.0+
- Rack 2.2+

**Breaking Changes**: None (initial release)

**Migration Guide**: Not applicable (initial release)

**Known Issues**: None

---

[0.1.0]: https://github.com/Tracekit-Dev/ruby-sdk/releases/tag/v0.1.0
