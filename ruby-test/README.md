# TraceKit Ruby Test Application

Rails API application for testing TraceKit Ruby SDK with cross-service communication.

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Copy environment variables:
```bash
cp .env.example .env
```

3. Configure your TraceKit API key in `.env`

## Running

Start the server on port 5002:

```bash
bundle exec rails server -p 5002
```

## Endpoints

- `GET /` - Service information
- `GET /health` - Health check
- `GET /test` - Code monitoring test (captures 3 snapshots)
- `GET /error-test` - Throws test exception
- `GET /checkout` - Checkout simulation with snapshots
- `GET /api/data` - Data endpoint (called by other services)
- `GET /api/call-go` - Call Go test service
- `GET /api/call-node` - Call Node test service
- `GET /api/call-python` - Call Python test service
- `GET /api/call-php` - Call PHP test service
- `GET /api/call-laravel` - Call Laravel test service
- `GET /api/call-java` - Call Java test service
- `GET /api/call-dotnet` - Call .NET test service
- `GET /api/call-all` - Call all test services

## Features Tested

- **Distributed Tracing**: Automatic HTTP request/response tracing
- **Metrics**: Request counts, active requests, duration histograms
- **Code Monitoring**: Snapshot capture with auto-registration
- **Security Scanning**: PII and credential detection
- **Cross-Service Communication**: Distributed tracing across services
