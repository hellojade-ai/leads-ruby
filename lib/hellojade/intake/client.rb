# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

module Hellojade
  module Intake
    # The HTTP client. Net::HTTP only, no runtime dependencies.
    #
    #   client = Hellojade::Intake::Client.new(api_key: ENV.fetch("HELLOJADE_API_KEY"))
    #   client.check_key                      # => true (422 from the API = key is valid)
    #   client.submit_lead(lead, idempotency_key: "acme-leads:1234")
    #
    # Every call retries transport errors and 5xx with exponential backoff and
    # waits out 429s according to Retry-After (see RetryPolicy). A 4xx other
    # than 429 is never retried.
    class Client
      DEFAULT_BASE_URL = "https://intake.hellojade.ai"
      DEFAULT_TIMEOUT = 20
      DEFAULT_USER_AGENT = "hellojade-intake-ruby/#{VERSION}".freeze

      INTAKE_PATH = "/v1/intake"
      VOCABULARY_PATH = "/v1/vocabulary"
      HEALTH_PATH = "/healthz"

      TRANSPORT_ERRORS = [
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
        Errno::ETIMEDOUT, Errno::EPIPE, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
        SocketError, IOError, EOFError, OpenSSL::SSL::SSLError, Timeout::Error
      ].freeze

      attr_reader :base_url, :timeout, :user_agent, :retry_policy

      # @param api_key [String] the key hellojade issued. Never logged, never in
      #   an error message.
      # @param base_url [String] https://intake.hellojade.ai; configuration, not a constant.
      # @param timeout [Numeric] seconds, applied to open/read/write. The API bounds
      #   its own handler at 20 s.
      # @param user_agent [String, nil] appended to the gem's own UA when given.
      # @param retry_policy [RetryPolicy]
      # @param sleeper [#call, nil] receives seconds to wait; injectable for tests.
      def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT, user_agent: nil,
                     retry_policy: RetryPolicy.new, sleeper: nil)
        raise ArgumentError, "api_key is required" if api_key.nil? || api_key.to_s.strip.empty?

        @api_key = api_key.to_s.strip
        @base_url = base_url.to_s.sub(%r{/+\z}, "")
        @base_uri = URI.parse(@base_url)
        unless @base_uri.is_a?(URI::HTTP) # URI::HTTPS < URI::HTTP
          raise ArgumentError, "base_url must be an http(s) URL, got #{base_url.inspect}"
        end

        @timeout = timeout
        @user_agent = user_agent ? "#{DEFAULT_USER_AGENT} #{user_agent}" : DEFAULT_USER_AGENT
        @retry_policy = retry_policy
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      end

      # Keep the key out of inspect/pp output and stack traces.
      def inspect
        "#<#{self.class.name} base_url=#{@base_url.inspect} api_key=[REDACTED]>"
      end
      alias to_s inspect

      # Section 1 of the integration brief: POST "{}" with the key. The API
      # authenticates BEFORE it validates, so a 422 proves the key is valid
      # and that nothing was stored. Returns true on 422, false on 401, and
      # raises ApiError for anything else.
      def check_key(request_id: nil)
        res = perform(:post, INTAKE_PATH, body: "{}", request_id: request_id)
        case res[:status]
        when 422 then true
        when 401 then false
        else raise error_for(res)
        end
      end

      # Submit one lead. Returns Accepted for both 202 ("accepted") and 200
      # ("duplicate" — the ORIGINAL event_id, which is success on a retry).
      #
      # @param lead [Lead, Hash]
      # @param idempotency_key [String] YOUR stable id for this lead, namespaced
      #   to you (e.g. "acme-leads:1234"). Not a timestamp, not a fresh UUID per
      #   attempt. Dedupe is per tenant, so a bare "1234" can collide with
      #   another source's lead and silently never be stored.
      # @param request_id [String, nil] your correlation id (<= 64 chars); one is
      #   generated when omitted. It comes back in the X-Request-Id header and in
      #   any error body.
      # @raise [ValidationError] 422 — fix the body, do not retry unchanged.
      # @raise [Unauthorized] 401.
      # @raise [RateLimited] 429 after the rate-limit wait budget is spent.
      # @raise [ApiError] any other non-success status.
      # @raise [TransportError] no response after the retry policy is exhausted.
      def submit_lead(lead, idempotency_key:, request_id: nil)
        key = idempotency_key.to_s
        raise ArgumentError, "idempotency_key is required (rule 2)" if key.strip.empty?
        raise ArgumentError, "idempotency_key must be <= 200 characters" if key.length > 200

        payload = lead.respond_to?(:to_h) ? lead.to_h : lead
        raise ArgumentError, "lead must be a Lead or a Hash" unless payload.is_a?(Hash)

        res = perform(:post, INTAKE_PATH, body: JSON.generate(payload), request_id: request_id,
                                          headers: { "Idempotency-Key" => key })
        case res[:status]
        when 200, 202
          Accepted.from_response(res[:status], res[:json] || {}, res[:request_id])
        else
          raise error_for(res)
        end
      end

      # GET /v1/vocabulary — unauthenticated, cacheable for five minutes. Fetch
      # it rather than hard-coding project_area terms.
      def vocabulary(request_id: nil)
        res = perform(:get, VOCABULARY_PATH, request_id: request_id, auth: false)
        raise error_for(res) unless res[:status] == 200

        Vocabulary.from_body(res[:json] || {})
      end

      # GET /healthz — liveness. Returns Health for both 200 and 503.
      def health(request_id: nil)
        res = perform(:get, HEALTH_PATH, request_id: request_id, auth: false, retry_5xx: false)
        raise error_for(res) unless [200, 503].include?(res[:status])

        Health.from_response(res[:status], res[:json] || {})
      end

      private

      # One logical request with the retry policy applied. Returns a Hash:
      # { status:, headers:, body:, json:, request_id:, attempts: }.
      def perform(method, path, body: nil, headers: {}, request_id: nil, auth: true, retry_5xx: true)
        request_id = (request_id || SecureRandom.hex(8)).to_s
        attempt = 0
        rate_limit_waits = 0

        loop do
          attempt += 1
          req = build_request(method, path, body, headers, request_id, auth)

          begin
            res = send_request(req)
          rescue *TRANSPORT_ERRORS => e
            if attempt >= retry_policy.max_attempts
              raise TransportError.new("intake request failed after #{attempt} attempt(s): #{e.class}: #{e.message}",
                                       request_id: request_id, attempts: attempt)
            end
            @sleeper.call(retry_policy.backoff(attempt))
            next
          end

          status = res.code.to_i
          parsed = parse(res, request_id, attempt)

          if status == 429
            rate_limit_waits += 1
            if rate_limit_waits > retry_policy.max_rate_limit_waits
              raise RateLimited.new(retry_after: retry_after(res), **error_args(parsed))
            end

            @sleeper.call(retry_policy.rate_limit_delay(retry_after(res), rate_limit_waits))
            attempt -= 1 # a 429 does not consume a delivery attempt
            next
          end

          if status >= 500 && retry_5xx && attempt < retry_policy.max_attempts
            @sleeper.call(retry_policy.backoff(attempt))
            next
          end

          return parsed
        end
      end

      def build_request(method, path, body, headers, request_id, auth)
        uri = URI.join("#{@base_url}/", path.sub(%r{\A/}, ""))
        req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
        req["User-Agent"] = user_agent
        req["Accept"] = "application/json"
        req["X-Request-Id"] = request_id
        req["X-API-Key"] = @api_key if auth
        headers.each { |k, v| req[k] = v }
        if body
          req["Content-Type"] = "application/json"
          req.body = body
        end
        req
      end

      def send_request(req)
        Net::HTTP.start(@base_uri.host, @base_uri.port,
                        use_ssl: @base_uri.scheme == "https",
                        open_timeout: timeout, read_timeout: timeout, write_timeout: timeout) do |http|
          http.request(req)
        end
      end

      def parse(res, request_id, attempt)
        body = res.body.to_s
        json = begin
          parsed = JSON.parse(body)
          parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError
          nil
        end
        # The API echoes a request id we sent; the header is present on every
        # response, including the 413 and per-IP 429 that carry no body id.
        rid = (json && json["request_id"]) || res["X-Request-Id"] || request_id
        { status: res.code.to_i, headers: res.each_header.to_h, body: body, json: json,
          request_id: rid, attempts: attempt, retry_after: retry_after(res) }
      end

      def retry_after(res)
        v = res["Retry-After"].to_s.strip
        v =~ /\A\d+\z/ ? v.to_i : 1
      end

      def error_args(res)
        json = res[:json] || {}
        { status: res[:status], code: json["error"] || "http_#{res[:status]}", message: json["message"],
          request_id: res[:request_id], body: res[:body], attempts: res[:attempts] }
      end

      def error_for(res)
        args = error_args(res)
        case res[:status]
        when 401 then Unauthorized.new(**args)
        when 422 then ValidationError.new(fields: (res[:json] || {})["fields"] || {}, **args)
        when 429 then RateLimited.new(retry_after: res[:retry_after], **args)
        else ApiError.new(**args)
        end
      end
    end
  end
end
