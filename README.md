# TraceKit Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/tracekit.svg)](https://rubygems.org/gems/tracekit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/Ruby-2.7+-red.svg)](https://www.ruby-lang.org/)

Official Ruby SDK for TraceKit APM - OpenTelemetry-based distributed tracing, metrics collection, and application performance monitoring for Ruby applications.

## Status

The SDK is production-ready with full support for distributed tracing, metrics, and code monitoring.

## Overview

TraceKit Ruby SDK provides production-ready distributed tracing, metrics, and code monitoring capabilities for Ruby and Rails applications. Built on OpenTelemetry standards, it offers seamless integration with Rails through automatic Railtie configuration, comprehensive security scanning, and a lightweight metrics API for tracking application performance.

## Features

- **OpenTelemetry-Native**: Built on OpenTelemetry for maximum compatibility
- **Distributed Tracing**: Full support for distributed trace propagation across microservices
- **Auto-Instrumentation**: Automatic tracing for Rails, Rack, PostgreSQL, MySQL, Redis, Sidekiq, and HTTP clients
- **Explicit Span Kinds**: Server spans explicitly marked with `kind: Server` for proper trace classification
- **Metrics API**: Counter, Gauge, and Histogram metrics with automatic OTLP export
- **Code Monitoring**: Live production debugging with non-breaking snapshots
- **Security Scanning**: Automatic detection of sensitive data (PII, credentials)
- **Local UI Auto-Detection**: Automatically sends traces to local TraceKit UI
- **Rails Auto-Configuration**: Zero-configuration setup via Railtie
- **Rack Middleware**: Automatic request instrumentation for any Rack application
- **Thread-Safe Metrics**: Concurrent metric collection with automatic buffering
- **Production-Ready**: Comprehensive error handling and graceful shutdown

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tracekit'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install tracekit
```

## Quick Start

### Rails Applications

The SDK automatically configures itself in Rails applications using environment variables:

**1. Create `.env` file:**

```bash
TRACEKIT_API_KEY=ctxio_abc123...
TRACEKIT_ENDPOINT=app.tracekit.dev
TRACEKIT_SERVICE_NAME=my-rails-app
TRACEKIT_ENVIRONMENT=production
TRACEKIT_CODE_MONITORING=true
```

**2. That's it!** The Railtie automatically:
- Loads configuration from ENV variables
- Initializes OpenTelemetry with OTLP exporters
- Adds Rack middleware for request instrumentation
- Sets up graceful shutdown

**3. Use the SDK in your controllers:**

```ruby
class CheckoutController < ApplicationController
  def create
    sdk = Tracekit.sdk

    # Capture snapshot with context
    sdk.capture_snapshot("checkout-start", {
      userId: params[:user_id],
      amount: params[:amount]
    })

    # Track metrics
    sdk.counter("checkout.requests").add(1)
    sdk.gauge("checkout.active").set(active_checkouts)

    # Your business logic here...

    sdk.capture_snapshot("checkout-complete", {
      userId: params[:user_id],
      paymentId: payment.id,
      status: "success"
    })

    render json: { status: "success" }
  end
end
```

### Vanilla Ruby Applications

For non-Rails applications, manually configure the SDK:

```ruby
require 'tracekit'

# Configure the SDK
Tracekit.configure do |config|
  config.api_key = ENV['TRACEKIT_API_KEY']
  config.service_name = 'my-service'
  config.endpoint = 'app.tracekit.dev'
  config.environment = 'production'
  config.enable_code_monitoring = true
end

# Use the SDK
sdk = Tracekit.sdk

# Capture snapshots
sdk.capture_snapshot("process-start", {
  jobId: job.id,
  status: "processing"
})

# Track metrics
counter = sdk.counter("jobs.processed", { type: "background" })
counter.add(1)

# At application shutdown
Tracekit.shutdown
```

### Rack Middleware (Sinatra, Grape, etc.)

For Rack-based frameworks:

```ruby
require 'tracekit'

Tracekit.configure do |config|
  config.api_key = ENV['TRACEKIT_API_KEY']
  config.service_name = 'my-sinatra-app'
end

# Add middleware
use Tracekit::Middleware

# Your application code...
```

## Configuration Options

```ruby
Tracekit.configure do |config|
  config.api_key = "ctxio_abc123..."              # Required: Your TraceKit API key
  config.service_name = "my-service"              # Required: Service identifier
  config.endpoint = "app.tracekit.dev"            # Optional: TraceKit endpoint
  config.use_ssl = true                           # Optional: Use HTTPS (default: true)
  config.environment = "production"               # Optional: Environment name
  config.service_version = "1.0.0"                # Optional: Service version
  config.enable_code_monitoring = true            # Optional: Enable snapshots
  config.code_monitoring_poll_interval = 30       # Optional: Polling interval (seconds)
  config.local_ui_port = 4000                     # Optional: Local UI port
  config.sampling_rate = 1.0                      # Optional: Trace sampling (0.0-1.0)
end
```

### Environment Variables (Rails Auto-Configuration)

| Variable | Description | Default |
|----------|-------------|---------|
| `TRACEKIT_API_KEY` | Your TraceKit API key (required) | - |
| `TRACEKIT_SERVICE_NAME` | Service identifier | - |
| `TRACEKIT_ENDPOINT` | TraceKit endpoint | `app.tracekit.dev` |
| `TRACEKIT_ENVIRONMENT` | Environment name | `development` |
| `TRACEKIT_CODE_MONITORING` | Enable code monitoring | `true` |
| `TRACEKIT_SAMPLING_RATE` | Trace sampling rate | `1.0` |

## Metrics API

### Counter (Monotonic)

```ruby
sdk = Tracekit.sdk

# Create counter with tags
counter = sdk.counter("http.requests.total", {
  service: "api",
  endpoint: "/users"
})

# Increment
counter.add(1)
counter.add(5)  # Add specific value
```

### Gauge (Point-in-Time Values)

```ruby
# Create gauge
gauge = sdk.gauge("memory.usage.bytes")

# Set value
gauge.set(1024 * 1024 * 512)  # 512 MB

# Increment/decrement
gauge.inc      # +1
gauge.inc(10)  # +10
gauge.dec      # -1
gauge.dec(5)   # -5
```

### Histogram (Distributions)

```ruby
# Create histogram with tags
histogram = sdk.histogram("http.request.duration", {
  unit: "ms"
})

# Record values
histogram.record(123.45)
histogram.record(67.89)
```

### Automatic Buffering

Metrics are automatically:
- Buffered in memory (up to 100 metrics or 10 seconds)
- Exported in OTLP JSON format
- Batched for efficiency
- Thread-safe for concurrent access

## Code Monitoring

TraceKit enables non-breaking snapshots of your application's runtime state:

```ruby
sdk = Tracekit.sdk

# Capture snapshot with variable state
sdk.capture_snapshot("checkout-start", {
  userId: 123,
  amount: 99.99,
  cart_items: ["item1", "item2"],
  status: "processing"
})
```

### Features

- **Automatic Context Capture**: File path, line number, function name extracted automatically
- **Security Scanning**: PII and credentials automatically detected and redacted
- **Trace Correlation**: Snapshots linked to active trace_id and span_id
- **Auto-Registration**: Breakpoints automatically registered on first capture
- **Zero Performance Impact**: When breakpoints are inactive, snapshots are skipped

### Security Detection

The SDK automatically detects and redacts:

**PII (Personally Identifiable Information)**:
- Email addresses
- Social Security Numbers (SSN)
- Credit card numbers
- Phone numbers

**Credentials**:
- API keys
- AWS access keys
- Stripe keys
- JWT tokens
- Private keys
- Passwords

Example:
```ruby
sdk.capture_snapshot("user-login", {
  email: "user@example.com",        # Redacted: [REDACTED]
  password: "secret123",             # Redacted: [REDACTED]
  api_key: "sk_live_abc123..."       # Redacted: [REDACTED]
})
```

## Distributed Tracing

The SDK automatically:
- Propagates W3C TraceContext headers (`traceparent`, `tracestate`)
- Creates spans for incoming HTTP requests (via middleware)
- Extracts trace context from upstream services
- Exports traces to TraceKit using OTLP/HTTP

### Auto-Instrumentation

The TraceKit Ruby SDK automatically instruments the following components when available:

**Web Frameworks:**
- **Rails** - Controller actions, request routing, and lifecycle events
- **Rack** - HTTP requests/responses with explicit `Server` span kind
- **ActionPack** - Controller and request/response processing
- **ActionView** - Template and view rendering

**HTTP Clients:**
- **Net::HTTP** - Standard library HTTP client with automatic trace propagation
- **HTTP gem** - HTTP gem client library

**Databases:**
- **ActiveRecord** - ORM layer operations (creates `Internal` spans)
- **PostgreSQL (PG)** - SQL queries with statement, system, and operation attributes (creates `Client` spans)
- **MySQL2** - MySQL database operations

**Background Jobs & Cache:**
- **Redis** - Cache operations and data access
- **Sidekiq** - Background job processing and queues

**Important:** The SDK's Rack middleware explicitly creates server spans with `kind: Server` for all incoming HTTP requests, ensuring consistent span classification across all Ruby frameworks (Rails, Sinatra, Grape, etc.).

### HTTP Client Instrumentation

OpenTelemetry automatically instruments HTTP clients:

```ruby
require 'net/http'

# Automatically traced - propagates trace context
uri = URI('http://localhost:8080/api/data')
response = Net::HTTP.get_response(uri)
```

### Span Hierarchy Example

A typical Rails request produces the following span hierarchy:

```
GET /users (kind: Server) - Root span from Tracekit::Middleware
  ├─ ApplicationController#users (kind: Internal) - Rails controller action
  ├─ User.all (kind: Internal) - ActiveRecord query
  │   └─ SELECT * FROM users (kind: Client) - PostgreSQL query span
  ├─ User.where (kind: Internal) - ActiveRecord query
  │   └─ SELECT * FROM users WHERE... (kind: Client) - PostgreSQL query span
  └─ users/index rendering (kind: Internal) - ActionView template rendering
```

**Span Kinds:**
- `Server` - Incoming HTTP requests (set explicitly by TraceKit middleware)
- `Client` - Outgoing HTTP requests and database queries
- `Internal` - Application-level operations (ORM, rendering, etc.)

## Project Structure

```
ruby-sdk/
├── lib/
│   ├── tracekit/
│   │   ├── config.rb              # Configuration with builder pattern
│   │   ├── endpoint_resolver.rb   # URL resolution logic
│   │   ├── sdk.rb                 # Main SDK class
│   │   ├── railtie.rb             # Rails auto-configuration
│   │   ├── middleware.rb          # Rack middleware
│   │   ├── metrics/               # Metrics implementation
│   │   ├── security/              # Security scanning
│   │   └── snapshots/             # Code monitoring
│   └── tracekit.rb                # Entry point
├── spec/                          # RSpec tests
├── ruby-test/                     # Cross-service test app
├── README.md
└── tracekit.gemspec
```

## Development Setup

### Prerequisites

- Ruby 2.7 or higher
- Bundler
- Git
- TraceKit API key

### Building from Source

```bash
# Clone the repository
git clone git@github.com:Tracekit-Dev/ruby-sdk.git
cd ruby-sdk

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run test application
cd ruby-test
bundle install
cp .env.example .env
# Edit .env with your API key
bundle exec rails server -p 5002
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/tracekit/endpoint_resolver_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

## Test Application

The `ruby-test/` directory contains a Rails API application for testing cross-service communication:

```bash
cd ruby-test
bundle exec rails server -p 5002
```

**Endpoints**:
- `GET /` - Service information
- `GET /health` - Health check
- `GET /test` - Code monitoring test
- `GET /error-test` - Exception test
- `GET /checkout` - Checkout simulation
- `GET /api/call-go` - Call Go test service
- `GET /api/call-node` - Call Node test service
- `GET /api/call-all` - Call all test services

See [ruby-test/README.md](ruby-test/README.md) for details.

## Requirements

- **Ruby**: 2.7 or later (tested up to 3.3)
- **Rails**: 6.0+ (for Rails integration)
- **Dependencies**:
  - opentelemetry-sdk (~> 1.2)
  - opentelemetry-exporter-otlp (~> 0.26)
  - opentelemetry-instrumentation-all (~> 0.50)
  - concurrent-ruby (~> 1.2)
  - httparty (~> 0.21) (test app only)

## Documentation

- [CHANGELOG](CHANGELOG.md) - Version history and release notes
- [TraceKit Documentation](https://app.tracekit.dev/docs)
- [Test Application README](ruby-test/README.md)

## Troubleshooting

### Rails not auto-configuring

Ensure your `.env` file is loaded:

```ruby
# config/application.rb
require 'dotenv/load' if defined?(Dotenv)
```

### Metrics not appearing

Check that:
1. API key is valid
2. Endpoint is reachable
3. Metrics are being flushed (wait 10 seconds or accumulate 100 metrics)

### Snapshots not capturing

Verify:
1. `TRACEKIT_CODE_MONITORING=true`
2. API key has snapshot permissions
3. Breakpoints are registered (check logs)

## Support

- **Documentation**: https://docs.tracekit.dev
- **Issues**: https://github.com/Tracekit-Dev/ruby-sdk/issues
- **Email**: support@tracekit.dev

## Contributing

We welcome contributions! To contribute:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built on [OpenTelemetry](https://opentelemetry.io/) - the industry standard for observability.

---

**Repository**: git@github.com:Tracekit-Dev/ruby-sdk.git
**Version**: v0.1.0
