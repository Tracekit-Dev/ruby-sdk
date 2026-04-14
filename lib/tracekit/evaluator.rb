# frozen_string_literal: true

module Tracekit
  # Expression evaluator for the TraceKit portable expression subset.
  # Evaluates breakpoint conditions locally to avoid server round-trips.
  #
  # Uses a custom recursive-descent parser -- never eval()/instance_eval.
  # Supports: comparison, logical, arithmetic, string concat, property access,
  # bracket notation, membership (in), null safety, and grouping.
  module Evaluator
    class UnsupportedExpressionError < StandardError; end

    # Returns true if the expression can be evaluated locally by the SDK.
    # Returns false for expressions containing function calls, regex operators,
    # assignment, array indexing, ternary, range, template literals, or bitwise operators.
    def self.sdk_evaluable?(expression)
      return true if expression.nil? || expression.strip.empty?

      # Function calls: word followed by opening paren
      return false if expression.match?(/\b[a-zA-Z_]\w*\s*\(/)

      # Regex match keyword
      return false if expression.match?(/\bmatches\b/)

      # Regex operator =~
      return false if expression.include?("=~")

      # Bitwise NOT ~ (but not inside =~, already handled above)
      expression.each_char.with_index do |ch, i|
        if ch == "~" && (i == 0 || expression[i - 1] != "=")
          return false
        end
      end

      # Bitwise AND: single & not part of &&
      i = 0
      while i < expression.length
        if expression[i] == "&"
          if i + 1 < expression.length && expression[i + 1] == "&"
            i += 2
            next
          end
          return false
        end
        i += 1
      end

      # Bitwise OR: single | not part of ||
      i = 0
      while i < expression.length
        if expression[i] == "|"
          if i + 1 < expression.length && expression[i + 1] == "|"
            i += 2
            next
          end
          return false
        end
        i += 1
      end

      # Bit shift
      return false if expression.include?("<<") || expression.include?(">>")

      # Template literals
      return false if expression.include?("${")

      # Range operator
      return false if expression.include?("..")

      # Ternary
      return false if expression.include?("?")

      # Array indexing [N]
      return false if expression.match?(/\[\d/)

      # Compound assignment
      return false if expression.match?(/[+\-*\/]=/)

      true
    end

    # Evaluates an expression string against the given environment
    # and returns a boolean result. Empty expressions return true.
    # Raises UnsupportedExpressionError for server-only expressions.
    def self.evaluate_condition(expression, env)
      return true if expression.nil? || expression.strip.empty?

      unless sdk_evaluable?(expression)
        raise UnsupportedExpressionError, "unsupported expression: requires server-side evaluation"
      end

      result = evaluate_expression(expression, env)

      case result
      when true, false
        result
      when nil
        false
      else
        # Non-boolean result from a condition -- treat as truthy
        true
      end
    end

    # Evaluates an expression and returns the raw result value.
    # Raises UnsupportedExpressionError for server-only expressions.
    def self.evaluate_expression(expression, env)
      return nil if expression.nil? || expression.strip.empty?

      unless sdk_evaluable?(expression)
        raise UnsupportedExpressionError, "unsupported expression: requires server-side evaluation"
      end

      tokens = Lexer.tokenize(expression)
      parser = Parser.new(tokens, env)
      parser.parse_expression
    end

    # Evaluates multiple expressions against the given environment.
    # Results are keyed by expression string. On error, nil is stored.
    def self.evaluate_expressions(expressions, env)
      results = {}
      expressions.each do |expr|
        results[expr] = evaluate_expression(expr, env)
      rescue StandardError
        results[expr] = nil
      end
      results
    end

    # Token types for the lexer
    module TokenType
      NUMBER    = :number
      STRING    = :string
      BOOL      = :bool
      NIL       = :nil
      IDENT     = :ident
      DOT       = :dot
      LBRACKET  = :lbracket
      RBRACKET  = :rbracket
      LPAREN    = :lparen
      RPAREN    = :rparen
      PLUS      = :plus
      MINUS     = :minus
      STAR      = :star
      SLASH     = :slash
      EQ        = :eq
      NEQ       = :neq
      LT        = :lt
      GT        = :gt
      LTE       = :lte
      GTE       = :gte
      AND       = :and
      OR        = :or
      NOT       = :not
      IN        = :in
      EOF       = :eof
    end

    Token = Struct.new(:type, :value, keyword_init: true)

    # Lexer: converts expression string into tokens.
    module Lexer
      def self.tokenize(input)
        tokens = []
        i = 0
        while i < input.length
          ch = input[i]

          # Skip whitespace
          if ch =~ /\s/
            i += 1
            next
          end

          # Two-character operators
          if i + 1 < input.length
            two = input[i, 2]
            case two
            when "=="
              tokens << Token.new(type: TokenType::EQ, value: "==")
              i += 2
              next
            when "!="
              tokens << Token.new(type: TokenType::NEQ, value: "!=")
              i += 2
              next
            when "<="
              tokens << Token.new(type: TokenType::LTE, value: "<=")
              i += 2
              next
            when ">="
              tokens << Token.new(type: TokenType::GTE, value: ">=")
              i += 2
              next
            when "&&"
              tokens << Token.new(type: TokenType::AND, value: "&&")
              i += 2
              next
            when "||"
              tokens << Token.new(type: TokenType::OR, value: "||")
              i += 2
              next
            end
          end

          # Single-character tokens
          case ch
          when "."
            tokens << Token.new(type: TokenType::DOT, value: ".")
            i += 1
            next
          when "["
            tokens << Token.new(type: TokenType::LBRACKET, value: "[")
            i += 1
            next
          when "]"
            tokens << Token.new(type: TokenType::RBRACKET, value: "]")
            i += 1
            next
          when "("
            tokens << Token.new(type: TokenType::LPAREN, value: "(")
            i += 1
            next
          when ")"
            tokens << Token.new(type: TokenType::RPAREN, value: ")")
            i += 1
            next
          when "+"
            tokens << Token.new(type: TokenType::PLUS, value: "+")
            i += 1
            next
          when "-"
            # Check if this is a negative number (unary minus before digits)
            if (tokens.empty? || [:plus, :minus, :star, :slash, :eq, :neq, :lt, :gt, :lte, :gte, :and, :or, :not, :lparen].include?(tokens.last&.type)) &&
               i + 1 < input.length && input[i + 1] =~ /\d/
              # Parse as negative number
              start = i
              i += 1
              i += 1 while i < input.length && (input[i] =~ /\d/ || input[i] == ".")
              num_str = input[start...i]
              value = num_str.include?(".") ? num_str.to_f : num_str.to_i
              tokens << Token.new(type: TokenType::NUMBER, value: value)
              next
            end
            tokens << Token.new(type: TokenType::MINUS, value: "-")
            i += 1
            next
          when "*"
            tokens << Token.new(type: TokenType::STAR, value: "*")
            i += 1
            next
          when "/"
            tokens << Token.new(type: TokenType::SLASH, value: "/")
            i += 1
            next
          when "<"
            tokens << Token.new(type: TokenType::LT, value: "<")
            i += 1
            next
          when ">"
            tokens << Token.new(type: TokenType::GT, value: ">")
            i += 1
            next
          when "!"
            tokens << Token.new(type: TokenType::NOT, value: "!")
            i += 1
            next
          end

          # String literals (double or single quoted)
          if ch == '"' || ch == "'"
            quote = ch
            i += 1
            start = i
            while i < input.length && input[i] != quote
              i += 1 if input[i] == "\\" # skip escaped char
              i += 1
            end
            tokens << Token.new(type: TokenType::STRING, value: input[start...i])
            i += 1 # skip closing quote
            next
          end

          # Numbers
          if ch =~ /\d/
            start = i
            i += 1 while i < input.length && (input[i] =~ /\d/ || input[i] == ".")
            num_str = input[start...i]
            value = num_str.include?(".") ? num_str.to_f : num_str.to_i
            tokens << Token.new(type: TokenType::NUMBER, value: value)
            next
          end

          # Identifiers and keywords
          if ch =~ /[a-zA-Z_]/
            start = i
            i += 1 while i < input.length && input[i] =~ /[a-zA-Z0-9_]/
            word = input[start...i]
            case word
            when "true"
              tokens << Token.new(type: TokenType::BOOL, value: true)
            when "false"
              tokens << Token.new(type: TokenType::BOOL, value: false)
            when "nil", "null", "None"
              tokens << Token.new(type: TokenType::NIL, value: nil)
            when "in"
              tokens << Token.new(type: TokenType::IN, value: "in")
            else
              tokens << Token.new(type: TokenType::IDENT, value: word)
            end
            next
          end

          raise "unexpected character: #{ch}"
        end

        tokens << Token.new(type: TokenType::EOF, value: nil)
        tokens
      end
    end

    # Recursive-descent parser and evaluator.
    # Operator precedence (lowest to highest):
    #   || -> && -> == != -> < > <= >= -> + - -> * / -> ! (unary) -> primary
    class Parser
      def initialize(tokens, env)
        @tokens = tokens
        @env = env
        @pos = 0
      end

      def parse_expression
        parse_or
      end

      private

      def current
        @tokens[@pos]
      end

      def advance
        t = @tokens[@pos]
        @pos += 1
        t
      end

      def match(*types)
        if types.include?(current.type)
          advance
        end
      end

      def expect(type)
        if current.type == type
          advance
        else
          raise "expected #{type}, got #{current.type} (#{current.value})"
        end
      end

      # OR: expr || expr
      def parse_or
        left = parse_and
        while current.type == TokenType::OR
          advance
          right = parse_and
          left = left || right
        end
        left
      end

      # AND: expr && expr
      def parse_and
        left = parse_equality
        while current.type == TokenType::AND
          advance
          right = parse_equality
          left = left && right
        end
        left
      end

      # Equality: == !=
      def parse_equality
        left = parse_comparison
        while (op = match(TokenType::EQ, TokenType::NEQ))
          right = parse_comparison
          left = case op.type
                 when TokenType::EQ then safe_equal?(left, right)
                 when TokenType::NEQ then !safe_equal?(left, right)
                 end
        end
        left
      end

      # Comparison: < > <= >=
      def parse_comparison
        left = parse_membership
        while (op = match(TokenType::LT, TokenType::GT, TokenType::LTE, TokenType::GTE))
          right = parse_membership
          left = safe_compare(op.type, left, right)
        end
        left
      end

      # Membership: "key" in map
      def parse_membership
        left = parse_addition
        if current.type == TokenType::IN
          advance
          right = parse_addition
          return membership_check(left, right)
        end
        left
      end

      # Addition/subtraction/string concatenation
      def parse_addition
        left = parse_multiplication
        while (op = match(TokenType::PLUS, TokenType::MINUS))
          right = parse_multiplication
          if op.type == TokenType::PLUS
            if left.is_a?(String) || right.is_a?(String)
              left = "#{left}#{right}"
            else
              left = numeric_val(left) + numeric_val(right)
            end
          else
            left = numeric_val(left) - numeric_val(right)
          end
        end
        left
      end

      # Multiplication/division
      def parse_multiplication
        left = parse_unary
        while (op = match(TokenType::STAR, TokenType::SLASH))
          right = parse_unary
          if op.type == TokenType::STAR
            left = numeric_val(left) * numeric_val(right)
          else
            divisor = numeric_val(right)
            return nil if divisor == 0
            left = numeric_val(left) / divisor
          end
        end
        left
      end

      # Unary: ! (NOT)
      def parse_unary
        if current.type == TokenType::NOT
          advance
          val = parse_unary
          return !val
        end
        parse_primary
      end

      # Primary: literals, identifiers (with property access), grouping
      def parse_primary
        tok = current

        case tok.type
        when TokenType::NUMBER
          advance
          resolve_postfix(tok.value)
        when TokenType::STRING
          advance
          resolve_postfix(tok.value)
        when TokenType::BOOL
          advance
          resolve_postfix(tok.value)
        when TokenType::NIL
          advance
          resolve_postfix(nil)
        when TokenType::IDENT
          advance
          value = resolve_identifier(tok.value)
          resolve_postfix(value)
        when TokenType::LPAREN
          advance
          result = parse_expression
          expect(TokenType::RPAREN)
          resolve_postfix(result)
        else
          raise "unexpected token: #{tok.type} (#{tok.value})"
        end
      end

      # Handle dot notation and bracket notation after a value
      def resolve_postfix(value)
        loop do
          if current.type == TokenType::DOT
            advance
            if current.type == TokenType::IDENT
              key = advance.value
              value = safe_access(value, key)
            else
              raise "expected identifier after dot"
            end
          elsif current.type == TokenType::LBRACKET
            advance
            key = parse_expression
            expect(TokenType::RBRACKET)
            value = safe_access(value, key.to_s)
          else
            break
          end
        end
        value
      end

      # Resolve a top-level identifier from the environment
      def resolve_identifier(name)
        if @env.key?(name)
          @env[name]
        elsif @env.key?(name.to_sym)
          @env[name.to_sym]
        else
          nil
        end
      end

      # Null-safe property access: accessing a key on nil returns nil
      def safe_access(obj, key)
        return nil if obj.nil?

        if obj.is_a?(Hash)
          if obj.key?(key)
            obj[key]
          elsif obj.key?(key.to_sym)
            obj[key.to_sym]
          else
            nil
          end
        else
          nil
        end
      end

      # Safe equality with type coercion rules:
      # - Integer/Float promotion allowed
      # - No other implicit coercion
      def safe_equal?(a, b)
        # nil handling
        return true if a.nil? && b.nil?
        return false if a.nil? || b.nil?

        # Integer/Float promotion
        if numeric?(a) && numeric?(b)
          return a.to_f == b.to_f
        end

        a == b
      end

      # Safe comparison for < > <= >=
      # Returns false for incompatible types
      def safe_compare(op, a, b)
        return false if a.nil? || b.nil?

        # Both numeric
        if numeric?(a) && numeric?(b)
          a_val = a.to_f
          b_val = b.to_f
          case op
          when TokenType::LT then a_val < b_val
          when TokenType::GT then a_val > b_val
          when TokenType::LTE then a_val <= b_val
          when TokenType::GTE then a_val >= b_val
          end
        elsif a.is_a?(String) && b.is_a?(String)
          case op
          when TokenType::LT then a < b
          when TokenType::GT then a > b
          when TokenType::LTE then a <= b
          when TokenType::GTE then a >= b
          end
        else
          false
        end
      end

      # Check if "key" in map
      def membership_check(key, map)
        return false unless map.is_a?(Hash)
        map.key?(key) || map.key?(key.to_s) || map.key?(key.to_sym)
      end

      def numeric?(val)
        val.is_a?(Integer) || val.is_a?(Float)
      end

      def numeric_val(val)
        return 0 if val.nil?
        val
      end
    end
  end
end
