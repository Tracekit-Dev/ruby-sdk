# frozen_string_literal: true

RSpec.describe Tracekit::Metrics::Counter do
  let(:registry) { instance_double(Tracekit::Metrics::Registry) }
  let(:counter) { described_class.new("test.counter", {}, registry) }

  describe "#inc" do
    it "increments by 1" do
      expect(registry).to receive(:record_metric).with("test.counter", "counter", 1.0, {})
      counter.inc
    end
  end

  describe "#add" do
    it "adds positive value" do
      expect(registry).to receive(:record_metric).with("test.counter", "counter", 5.0, {})
      counter.add(5.0)
    end

    it "raises error for negative value" do
      expect {
        counter.add(-1.0)
      }.to raise_error(ArgumentError, "Counter values must be non-negative")
    end

    it "accumulates values" do
      expect(registry).to receive(:record_metric).with("test.counter", "counter", 1.0, {})
      expect(registry).to receive(:record_metric).with("test.counter", "counter", 6.0, {})

      counter.inc
      counter.add(5.0)
    end
  end
end
