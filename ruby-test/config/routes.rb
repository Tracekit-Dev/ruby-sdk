# frozen_string_literal: true

Rails.application.routes.draw do
  root "application#index"

  get "/health", to: "application#health"
  get "/test", to: "application#test"
  get "/error-test", to: "application#error_test"
  get "/checkout", to: "application#checkout"
  get "/users", to: "application#users"
  get "/security-test", to: "application#security_test"

  namespace :api do
    get "/data", to: "api#data"
    get "/call-go", to: "api#call_go"
    get "/call-node", to: "api#call_node"
    get "/call-python", to: "api#call_python"
    get "/call-php", to: "api#call_php"
    get "/call-laravel", to: "api#call_laravel"
    get "/call-java", to: "api#call_java"
    get "/call-dotnet", to: "api#call_dotnet"
    get "/call-all", to: "api#call_all"
    get "/llm", to: "llm#show"
  end
end
