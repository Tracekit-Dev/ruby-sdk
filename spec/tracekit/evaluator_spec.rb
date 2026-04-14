# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Tracekit::Evaluator do
  let(:fixtures) do
    path = File.join(File.dirname(__FILE__), "../../testdata/expression_fixtures.json")
    JSON.parse(File.read(path))
  end

  let(:default_env) do
    # Convert string keys to match what SDKs receive (string-keyed hashes)
    fixtures["default_variables"]
  end

  describe ".sdk_evaluable?" do
    it "returns true for empty expression" do
      expect(described_class.sdk_evaluable?("")).to be true
      expect(described_class.sdk_evaluable?(nil)).to be true
    end

    it "returns true for portable expressions" do
      expect(described_class.sdk_evaluable?("status == 200")).to be true
      expect(described_class.sdk_evaluable?('method == "GET"')).to be true
      expect(described_class.sdk_evaluable?("status == 200 && method == \"GET\"")).to be true
    end

    it "returns false for function calls" do
      expect(described_class.sdk_evaluable?("matches(path, '/api')")).to be false
      expect(described_class.sdk_evaluable?("len(user.profile.tags) > 1")).to be false
      expect(described_class.sdk_evaluable?('contains(user.email, "@")')).to be false
    end

    it "returns false for regex operators" do
      expect(described_class.sdk_evaluable?('path =~ "/api/.*"')).to be false
    end

    it "returns false for bitwise operators" do
      expect(described_class.sdk_evaluable?("flags & 0x01")).to be false
      expect(described_class.sdk_evaluable?("flags | 0x02")).to be false
      expect(described_class.sdk_evaluable?("value << 2")).to be false
      expect(described_class.sdk_evaluable?("value >> 1")).to be false
    end

    it "returns false for ternary, range, template literals" do
      expect(described_class.sdk_evaluable?('status > 400 ? "error" : "ok"')).to be false
      expect(described_class.sdk_evaluable?("1..10")).to be false
      expect(described_class.sdk_evaluable?('`Hello ${user.name}`')).to be false
    end

    it "returns false for array indexing" do
      expect(described_class.sdk_evaluable?("items[0]")).to be false
    end

    it "returns false for compound assignment" do
      expect(described_class.sdk_evaluable?("status += 1")).to be false
    end
  end

  describe ".evaluate_condition" do
    it "returns true for empty expression" do
      expect(described_class.evaluate_condition("", default_env)).to be true
      expect(described_class.evaluate_condition(nil, default_env)).to be true
    end

    it "raises UnsupportedExpressionError for server-only expressions" do
      expect {
        described_class.evaluate_condition("matches(path, '/api')", default_env)
      }.to raise_error(Tracekit::Evaluator::UnsupportedExpressionError)
    end
  end

  describe ".evaluate_expressions" do
    it "evaluates multiple expressions and returns a hash" do
      results = described_class.evaluate_expressions(
        ["status + 100", "method"],
        default_env
      )
      expect(results["status + 100"]).to eq(300)
      expect(results["method"]).to eq("GET")
    end

    it "returns nil for expressions that error" do
      results = described_class.evaluate_expressions(
        ["matches(path, '/api')"],
        default_env
      )
      expect(results["matches(path, '/api')"]).to be_nil
    end
  end

  describe "fixture test suite" do
    it "passes all 64 fixture test cases" do
      test_cases = fixtures["test_cases"]
      expect(test_cases.length).to be >= 64

      failures = []

      test_cases.each do |tc|
        id = tc["id"]
        expression = tc["expression"]
        expected = tc["expected"]
        classify = tc["classify"]
        env = tc["variables"] || default_env

        if classify == "server-only"
          # Verify expression is classified as non-evaluable
          unless !described_class.sdk_evaluable?(expression)
            failures << "#{id}: expected server-only, but sdk_evaluable? returned true for: #{expression}"
          end
        else
          # Verify expression is classified as sdk-evaluable
          unless described_class.sdk_evaluable?(expression)
            failures << "#{id}: expected sdk-evaluable, but sdk_evaluable? returned false for: #{expression}"
            next
          end

          # Evaluate and compare result
          begin
            result = described_class.evaluate_expression(expression, env)

            # Normalize for comparison: integer/float promotion
            if expected.is_a?(Float) && result.is_a?(Integer)
              result = result.to_f
            elsif expected.is_a?(Integer) && result.is_a?(Float) && result == result.to_i
              result = result.to_i
            end

            unless result == expected
              failures << "#{id}: expression '#{expression}' expected #{expected.inspect} (#{expected.class}), got #{result.inspect} (#{result.class})"
            end
          rescue => e
            failures << "#{id}: expression '#{expression}' raised #{e.class}: #{e.message}"
          end
        end
      end

      if failures.any?
        fail "#{failures.length} fixture(s) failed:\n#{failures.join("\n")}"
      end
    end
  end
end
