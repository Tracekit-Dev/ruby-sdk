# frozen_string_literal: true

require "httparty"

module Api
  class ApiController < ActionController::API
  GO_SERVICE_URL = "http://localhost:8082"
  NODE_SERVICE_URL = "http://localhost:8084"
  PYTHON_SERVICE_URL = "http://localhost:5001"
  PHP_SERVICE_URL = "http://localhost:8086"
  LARAVEL_SERVICE_URL = "http://localhost:8083"
  JAVA_SERVICE_URL = "http://localhost:8080"
  DOTNET_SERVICE_URL = "http://localhost:8087"

  def data
    sleep(rand(10..50) / 1000.0) # Simulate processing

    render json: {
      service: "ruby-test-app",
      timestamp: Time.now.utc.iso8601,
      data: {
        framework: "Rails",
        version: Rails::VERSION::STRING,
        randomValue: rand(1..100)
      }
    }
  end

  def call_go
    call_service("go-test-app", GO_SERVICE_URL)
  end

  def call_node
    call_service("node-test-app", NODE_SERVICE_URL)
  end

  def call_python
    call_service("python-test-app", PYTHON_SERVICE_URL)
  end

  def call_php
    call_service("php-test-app", PHP_SERVICE_URL)
  end

  def call_laravel
    call_service("laravel-test-app", LARAVEL_SERVICE_URL)
  end

  def call_java
    call_service("java-test-app", JAVA_SERVICE_URL)
  end

  def call_dotnet
    call_service("dotnet-test-app", DOTNET_SERVICE_URL)
  end

  def call_all
    services = [
      { name: "go-test-app", url: GO_SERVICE_URL },
      { name: "node-test-app", url: NODE_SERVICE_URL },
      { name: "python-test-app", url: PYTHON_SERVICE_URL },
      { name: "php-test-app", url: PHP_SERVICE_URL },
      { name: "laravel-test-app", url: LARAVEL_SERVICE_URL },
      { name: "java-test-app", url: JAVA_SERVICE_URL },
      { name: "dotnet-test-app", url: DOTNET_SERVICE_URL }
    ]

    results = services.map do |service|
      begin
        response = HTTParty.get("#{service[:url]}/api/data", timeout: 5)
        {
          service: service[:name],
          status: response.code,
          response: JSON.parse(response.body)
        }
      rescue => e
        {
          service: service[:name],
          error: e.message
        }
      end
    end

    render json: {
      service: "ruby-test-app",
      chain: results
    }
  end

  private

  def call_service(service_name, service_url)
    response = HTTParty.get("#{service_url}/api/data", timeout: 5)

    render json: {
      service: "ruby-test-app",
      called: service_name,
      response: JSON.parse(response.body),
      status: response.code
    }
  rescue => e
    render json: {
      service: "ruby-test-app",
      called: service_name,
      error: e.message
    }, status: :internal_server_error
  end
  end
end
