# frozen_string_literal: true

class ApplicationController < ActionController::API
  def index
    render json: {
      service: "ruby-test-app",
      message: "TraceKit Ruby Test Application",
      features: ["tracing", "snapshots", "metrics"],
      endpoints: {
        "GET /" => "This endpoint",
        "GET /health" => "Health check",
        "GET /test" => "Code monitoring test",
        "GET /error-test" => "Error test",
        "GET /checkout" => "Checkout simulation",
        "GET /api/data" => "Data endpoint",
        "GET /api/call-go" => "Call Go service",
        "GET /api/call-node" => "Call Node service",
        "GET /api/call-python" => "Call Python service",
        "GET /api/call-php" => "Call PHP service",
        "GET /api/call-laravel" => "Call Laravel service",
        "GET /api/call-java" => "Call Java service",
        "GET /api/call-dotnet" => "Call .NET service",
        "GET /api/call-all" => "Call all services",
        "GET /users" => "List users (database query test)"
      }
    }
  end

  def health
    render json: {
      status: "healthy",
      service: "ruby-test-app",
      timestamp: Time.now.utc.iso8601
    }
  end

  def test
    # Create custom trace span
    tracer = OpenTelemetry.tracer_provider.tracer('ruby-sdk', '1.0.0')

    tracer.in_span('test_endpoint', attributes: {
      'http.method' => 'GET',
      'http.route' => '/test',
      'endpoint.name' => 'test'
    }, kind: :server) do |span|

      sdk = Tracekit.sdk

      # Track request counter metric
      request_counter = sdk.counter("http.requests.total", { endpoint: "/test", method: "GET" })
      request_counter.inc

      span.add_event('snapshot_capture_started')
      sdk.capture_snapshot("test-route-entry", {
        route: "test",
        method: "GET",
        timestamp: Time.now.utc
      })

      # Simulate processing in a child span
      tracer.in_span('process_test_data') do |child_span|
        user_id = rand(1..1000)
        cart_total = rand(10..500)

        child_span.set_attribute('user.id', user_id)
        child_span.set_attribute('cart.total', cart_total)

        # Track active requests gauge
        active_requests = sdk.gauge("http.requests.active", { endpoint: "/test" })
        active_requests.set(1)

        sdk.capture_snapshot("test-processing", {
          userId: user_id,
          cartTotal: cart_total,
          processingStep: "validation"
        })

        sdk.capture_snapshot("test-complete", {
          userId: user_id,
          totalProcessed: cart_total,
          status: "success"
        })

        active_requests.set(0)

        span.add_event('processing_completed', attributes: {
          'user.id' => user_id,
          'cart.total' => cart_total
        })

        render json: {
          message: "Code monitoring test completed!",
          data: { userId: user_id, cartTotal: cart_total }
        }
      end
    end
  end

  def error_test
    Tracekit.sdk.capture_snapshot("error-test-start", {
      route: "error-test",
      intent: "trigger_exception"
    })

    raise StandardError, "This is a test exception for code monitoring!"
  end

  def checkout
    # Create custom trace span
    tracer = OpenTelemetry.tracer_provider.tracer('ruby-sdk', '1.0.0')

    tracer.in_span('checkout_endpoint', attributes: {
      'http.method' => 'GET',
      'http.route' => '/checkout',
      'endpoint.name' => 'checkout'
    }, kind: :server) do |span|

      sdk = Tracekit.sdk
      user_id = params[:user_id]&.to_i || 123
      amount = params[:amount]&.to_f || 99.99

      span.set_attribute('user.id', user_id)
      span.set_attribute('payment.amount', amount)

      # Track checkout metrics
      checkout_counter = sdk.counter("checkout.total", { status: "initiated" })
      checkout_counter.inc

      start_time = Time.now

      sdk.capture_snapshot("checkout-start", {
        userId: user_id,
        amount: amount
      })

      # Payment processing span
      tracer.in_span('process_payment', attributes: {
        'payment.amount' => amount,
        'payment.currency' => 'USD'
      }) do |payment_span|

        result = {
          paymentId: "pay_#{SecureRandom.hex(16)}",
          amount: amount,
          status: "completed",
          timestamp: Time.now.utc.iso8601
        }

        payment_span.set_attribute('payment.id', result[:paymentId])
        payment_span.set_attribute('payment.status', 'completed')

        # Track checkout duration
        duration_ms = ((Time.now - start_time) * 1000).to_i
        duration_histogram = sdk.histogram("checkout.duration_ms", { status: "completed" })
        duration_histogram.record(duration_ms)

        # Track payment amount
        amount_histogram = sdk.histogram("checkout.amount", { currency: "USD" })
        amount_histogram.record(amount)

        sdk.capture_snapshot("checkout-complete", {
          userId: user_id,
          amount: amount,
          paymentId: result[:paymentId],
          status: result[:status]
        })

        # Track successful checkouts
        completed_counter = sdk.counter("checkout.total", { status: "completed" })
        completed_counter.inc

        span.add_event('checkout_completed', attributes: {
          'payment.id' => result[:paymentId]
        })

        render json: result
      end
    end
  end

  def users
    # This endpoint demonstrates database tracing
    # Will generate SQL query spans automatically via ActiveRecord instrumentation

    # SELECT ALL users
    all_users = User.all.to_a

    # SELECT with WHERE clause
    adult_users = User.where("age >= ?", 18).to_a

    # COUNT query
    total_count = User.count

    # FIND by ID
    first_user = User.find_by(id: 1)

    render json: {
      message: "Database queries traced successfully",
      total_users: total_count,
      all_users: all_users.map { |u| { id: u.id, name: u.name, email: u.email, age: u.age } },
      adult_users_count: adult_users.count,
      first_user: first_user ? { id: first_user.id, name: first_user.name } : nil
    }
  end
end
