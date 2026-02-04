# frozen_string_literal: true

module Tracekit
  module Snapshots
    # Represents a breakpoint configuration from the backend
    BreakpointConfig = Struct.new(
      :id, :file_path, :line_number, :function_name, :label,
      :enabled, :max_captures, :capture_count, :expire_at,
      keyword_init: true
    )

    # Represents a snapshot capture
    Snapshot = Struct.new(
      :breakpoint_id, :service_name, :file_path, :function_name, :label,
      :line_number, :variables, :security_flags, :stack_trace,
      :trace_id, :span_id, :captured_at,
      keyword_init: true
    )

    # Represents a breakpoint registration request
    BreakpointRegistration = Struct.new(
      :service_name, :file_path, :line_number, :function_name, :label,
      keyword_init: true
    )
  end
end
