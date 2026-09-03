# frozen_string_literal: true

module Hellojade
  module Intake
    # Base class for everything this gem raises.
    class Error < StandardError; end

    # The request never produced an HTTP response: DNS, connect, TLS, timeout,
    # reset. The client retries these (rule 5) and raises only once the retry
    # policy is exhausted. The original exception is available as +cause+.
    class TransportError < Error
      attr_reader :request_id, :attempts

      def initialize(message, request_id: nil, attempts: 1)
        super(message)
        @request_id = request_id
        @attempts = attempts
      end
    end

    # The API answered with a non-success status. +code+ is the API's own
    # error string ("unauthorized", "invalid_json", "body_too_large",
    # "not_accepting", ...). +request_id+ is the handle support needs when
    # there is no event_id. The API key is never part of the message.
    class ApiError < Error
      attr_reader :status, :code, :request_id, :body, :attempts

      def initialize(status:, code:, message: nil, request_id: nil, body: nil, attempts: 1)
        @status = status
        @code = code
        @request_id = request_id
        @body = body
        @attempts = attempts
        text = "intake API #{status} #{code}"
        text += ": #{message}" if message && !message.empty?
        text += " (request_id=#{request_id})" if request_id
        super(text)
      end

      # Only 5xx is worth retrying; every other status is a fact about the
      # request that a retry will not change.
      def retryable?
        status >= 500
      end
    end

    # 401 — the key is missing, mistyped, revoked, or pointed at the wrong host.
    class Unauthorized < ApiError; end

    # 422 — +fields+ maps every failing field to a reason ("required",
    # "too_long", "out_of_range"). The API lists all of them at once; do not
    # stop at the first.
    class ValidationError < ApiError
      attr_reader :fields

      def initialize(fields: {}, **rest)
        @fields = fields
        super(**rest)
      end

      def message
        return super if fields.empty?

        "#{super} fields=#{fields.map { |k, v| "#{k}:#{v}" }.join(',')}"
      end
    end

    # 429 — raised only after the retry policy's rate-limit budget is spent.
    # +retry_after+ is the server's floor in seconds.
    class RateLimited < ApiError
      attr_reader :retry_after

      def initialize(retry_after: 1, **rest)
        @retry_after = retry_after
        super(**rest)
      end
    end
  end
end
