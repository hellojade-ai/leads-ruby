# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  include StubClientTest
  include Hellojade::Intake

  # --- construction -------------------------------------------------------

  def test_requires_an_api_key
    assert_raises(ArgumentError) { Client.new(api_key: "") }
    assert_raises(ArgumentError) { Client.new(api_key: nil) }
  end

  def test_rejects_a_non_http_base_url
    assert_raises(ArgumentError) { Client.new(api_key: "k", base_url: "ftp://x") }
  end

  def test_defaults
    c = Client.new(api_key: "k")
    assert_equal "https://intake.hellojade.ai", c.base_url
    assert_equal 20, c.timeout
    assert_match(%r{\Ahellojade-intake-ruby/\d}, c.user_agent)
  end

  def test_inspect_never_shows_the_key
    refute_includes @client.inspect, TEST_KEY
    refute_includes @client.to_s, TEST_KEY
  end

  # --- submit_lead: success ------------------------------------------------

  def test_202_returns_accepted_and_sends_the_right_headers_and_body
    @stub.enqueue(202, accepted_body)
    res = @client.submit_lead(sample_lead, idempotency_key: "acme-leads:A-99812", request_id: "acme/req/1")

    assert res.accepted?
    refute res.duplicate?
    assert_equal 202, res.http_status
    assert_equal "evt_0198f2c1a4b00000a3d19f4c2b7e", res.event_id
    assert_equal "acme-leads", res.source
    assert_equal [], res.flags
    assert_equal "acme/req/1", res.request_id

    req = @stub.requests.fetch(0)
    assert_equal "POST", req.http_method
    assert_equal "/v1/intake", req.path
    assert_equal TEST_KEY, req.headers["x-api-key"]
    assert_equal "acme-leads:A-99812", req.headers["idempotency-key"]
    assert_equal "acme/req/1", req.headers["x-request-id"]
    assert_equal "application/json", req.headers["content-type"]
    assert_match(%r{\Ahellojade-intake-ruby/}, req.headers["user-agent"])
    body = req.json
    assert_equal "Dana", body["first_name"]
    assert_equal "(630) 555-0142", body["phone"]
    assert_equal "XZ-1", body["partner_job_id"]
    assert_equal 25_000, body["budget"]
    refute body.key?("source")
    refute body.key?("extra")
    refute body.key?("cost")
  end

  def test_200_duplicate_is_success_with_the_original_event_id
    @stub.enqueue(200, accepted_body(status: "duplicate"))
    res = @client.submit_lead(sample_lead, idempotency_key: "acme-leads:A-99812")
    assert res.duplicate?
    assert_equal 200, res.http_status
    assert_equal "evt_0198f2c1a4b00000a3d19f4c2b7e", res.event_id
  end

  def test_flags_are_returned_not_raised
    @stub.enqueue(202, accepted_body(flags: %w[phone_unnormalized extra_fields_preserved]))
    res = @client.submit_lead(sample_lead, idempotency_key: "acme-leads:1")
    assert_equal %w[phone_unnormalized extra_fields_preserved], res.flags
    assert_empty @sleeper.calls
  end

  def test_accepts_a_plain_hash
    @stub.enqueue(202, accepted_body)
    @client.submit_lead({ "first_name" => "D", "last_name" => "W", "phone" => "1" }, idempotency_key: "acme:1")
    assert_equal "D", @stub.requests.fetch(0).json["first_name"]
  end

  def test_generates_a_request_id_when_none_is_given
    @stub.enqueue(202, accepted_body)
    res = @client.submit_lead(sample_lead, idempotency_key: "acme:1")
    rid = @stub.requests.fetch(0).headers["x-request-id"]
    assert_match(/\A\h{16}\z/, rid)
    assert_equal rid, res.request_id
  end

  def test_idempotency_key_is_required
    assert_raises(ArgumentError) { @client.submit_lead(sample_lead, idempotency_key: "") }
    assert_raises(ArgumentError) { @client.submit_lead(sample_lead, idempotency_key: "x" * 201) }
    assert_empty @stub.requests
  end

  # --- submit_lead: 4xx are never retried ----------------------------------

  def test_400_raises_api_error_without_retry
    @stub.enqueue(400, { "error" => "invalid_json", "request_id" => "9f2c1a4b" })
    err = assert_raises(ApiError) { @client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal 400, err.status
    assert_equal "invalid_json", err.code
    assert_equal "9f2c1a4b", err.request_id
    refute err.retryable?
    assert_equal 1, @stub.requests.size
    assert_empty @sleeper.calls
  end

  def test_401_raises_unauthorized_and_never_leaks_the_key
    @stub.enqueue(401, { "error" => "unauthorized", "request_id" => "9f2c1a4b" })
    err = assert_raises(Unauthorized) { @client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_kind_of ApiError, err
    assert_equal 401, err.status
    refute_includes err.message, TEST_KEY
    refute_includes err.inspect, TEST_KEY
    assert_equal 1, @stub.requests.size
  end

  def test_413_raises_api_error_with_request_id_from_the_header
    @stub.enqueue(413, { "error" => "body_too_large" })
    err = assert_raises(ApiError) { @client.submit_lead(sample_lead, idempotency_key: "acme:1", request_id: "r-413") }
    assert_equal 413, err.status
    assert_equal "body_too_large", err.code
    assert_equal "r-413", err.request_id
    assert_equal 1, @stub.requests.size
  end

  def test_422_raises_validation_error_with_every_field
    @stub.enqueue(422, { "error" => "validation_failed", "request_id" => "9f2c1a4b",
                         "fields" => { "first_name" => "required", "last_name" => "required", "phone" => "required" } })
    err = assert_raises(ValidationError) { @client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal 422, err.status
    assert_equal "validation_failed", err.code
    assert_equal({ "first_name" => "required", "last_name" => "required", "phone" => "required" }, err.fields)
    assert_includes err.message, "phone:required"
    assert_equal 1, @stub.requests.size
    assert_empty @sleeper.calls
  end

  # --- 429 -----------------------------------------------------------------

  def test_429_waits_retry_after_and_does_not_consume_an_attempt
    @stub.enqueue(429, { "error" => "rate_limited" }, headers: { "Retry-After" => "3" })
    @stub.enqueue(429, { "error" => "rate_limited" }, headers: { "Retry-After" => "1" })
    @stub.enqueue(202, accepted_body)
    res = @client.submit_lead(sample_lead, idempotency_key: "acme:1")
    assert res.accepted?
    assert_equal 3, @stub.requests.size
    # first wait: max(Retry-After 3, backoff(1)=1) = 3; second: max(1, backoff(2)=2) = 2
    assert_equal [3.0, 2.0], @sleeper.calls
    keys = @stub.requests.map { |r| r.headers["idempotency-key"] }.uniq
    assert_equal ["acme:1"], keys
  end

  def test_429_without_retry_after_defaults_to_one_second_floor
    @stub.enqueue(429, { "error" => "rate_limited" })
    @stub.enqueue(202, accepted_body)
    @client.submit_lead(sample_lead, idempotency_key: "acme:1")
    assert_equal [1.0], @sleeper.calls
  end

  def test_429_raises_rate_limited_once_the_wait_budget_is_spent
    client = Client.new(api_key: TEST_KEY, base_url: @stub.url, sleeper: @sleeper,
                        retry_policy: RetryPolicy.new(max_rate_limit_waits: 2, jitter: 0))
    3.times { @stub.enqueue(429, { "error" => "rate_limited" }, headers: { "Retry-After" => "5" }) }
    err = assert_raises(RateLimited) { client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal 429, err.status
    assert_equal 5, err.retry_after
    assert_equal 3, @stub.requests.size
    assert_equal 2, @sleeper.calls.size
  end

  # --- 5xx and transport errors are retried with backoff -------------------

  def test_503_retries_with_growing_backoff_then_succeeds
    @stub.enqueue(503, { "error" => "not_accepting" })
    @stub.enqueue(503, { "error" => "not_accepting" })
    @stub.enqueue(202, accepted_body)
    res = @client.submit_lead(sample_lead, idempotency_key: "acme:1")
    assert res.accepted?
    assert_equal 3, @stub.requests.size
    assert_equal [1.0, 2.0], @sleeper.calls
  end

  def test_503_raises_after_max_attempts
    5.times { @stub.enqueue(503, { "error" => "not_accepting" }) }
    err = assert_raises(ApiError) { @client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal 503, err.status
    assert_equal "not_accepting", err.code
    assert err.retryable?
    assert_equal 5, err.attempts
    assert_equal 5, @stub.requests.size
    assert_equal [1.0, 2.0, 4.0, 8.0], @sleeper.calls
  end

  def test_backoff_is_capped_at_max_delay
    client = Client.new(api_key: TEST_KEY, base_url: @stub.url, sleeper: @sleeper,
                        retry_policy: RetryPolicy.new(max_attempts: 8, jitter: 0))
    8.times { @stub.enqueue(500, { "error" => "boom" }) }
    assert_raises(ApiError) { client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal [1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 30.0], @sleeper.calls
  end

  def test_connection_refused_is_retried_then_raises_transport_error
    closed = TCPServer.new("127.0.0.1", 0)
    port = closed.addr[1]
    closed.close
    client = Client.new(api_key: TEST_KEY, base_url: "http://127.0.0.1:#{port}", sleeper: @sleeper,
                        retry_policy: RetryPolicy.new(max_attempts: 3, jitter: 0))
    err = assert_raises(TransportError) { client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal 3, err.attempts
    assert_equal [1.0, 2.0], @sleeper.calls
    refute_includes err.message, TEST_KEY
  end

  def test_timeout_is_retried_with_the_same_idempotency_key
    client = Client.new(api_key: TEST_KEY, base_url: @stub.url, timeout: 0.2, sleeper: @sleeper,
                        retry_policy: RetryPolicy.new(jitter: 0))
    @stub.enqueue(202, accepted_body, delay: 1.0)
    @stub.enqueue(202, accepted_body)
    res = client.submit_lead(sample_lead, idempotency_key: "acme:1")
    assert res.accepted?
    assert_equal [1.0], @sleeper.calls
    sleep 1.1 # let the slow handler finish before the stub is shut down
    assert_equal(["acme:1", "acme:1"], @stub.requests.map { |r| r.headers["idempotency-key"] })
  end

  def test_no_retry_policy_makes_exactly_one_attempt
    client = Client.new(api_key: TEST_KEY, base_url: @stub.url, sleeper: @sleeper, retry_policy: RetryPolicy.none)
    @stub.enqueue(503, { "error" => "not_accepting" })
    assert_raises(ApiError) { client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal 1, @stub.requests.size
    assert_empty @sleeper.calls
  end

  # --- check_key -----------------------------------------------------------

  def test_check_key_true_on_422_and_stores_nothing
    @stub.enqueue(422, { "error" => "validation_failed", "request_id" => "x",
                         "fields" => { "first_name" => "required", "last_name" => "required", "phone" => "required" } })
    assert_equal true, @client.check_key
    req = @stub.requests.fetch(0)
    assert_equal "{}", req.body
    assert_equal TEST_KEY, req.headers["x-api-key"]
    assert_nil req.headers["idempotency-key"]
  end

  def test_check_key_false_on_401
    @stub.enqueue(401, { "error" => "unauthorized", "request_id" => "x" })
    assert_equal false, @client.check_key
  end

  def test_check_key_waits_out_a_429
    @stub.enqueue(429, { "error" => "rate_limited" }, headers: { "Retry-After" => "1" })
    @stub.enqueue(422, { "error" => "validation_failed", "fields" => { "phone" => "required" } })
    assert_equal true, @client.check_key
    assert_equal [1.0], @sleeper.calls
  end

  def test_check_key_raises_on_anything_else
    @stub.enqueue(202, accepted_body)
    assert_raises(ApiError) { @client.check_key }
  end

  # --- vocabulary / health -------------------------------------------------

  def test_vocabulary_is_unauthenticated_and_typed
    @stub.enqueue(200, { "project_area" => [{ "area" => "roof", "status" => "confirmed" },
                                            { "area" => "solar", "status" => "proposed" }],
                         "project_service" => %w[replacement repair remodel maintain],
                         "required" => %w[first_name last_name phone] })
    v = @client.vocabulary
    assert_equal %w[roof solar], v.areas
    assert v.area?("solar")
    assert_equal "proposed", v.project_area[1].status
    assert_equal %w[replacement repair remodel maintain], v.project_service
    assert_equal %w[first_name last_name phone], v.required
    req = @stub.requests.fetch(0)
    assert_equal "GET", req.http_method
    assert_equal "/v1/vocabulary", req.path
    assert_nil req.headers["x-api-key"]
  end

  def test_vocabulary_503_is_retried_then_raised
    5.times { @stub.enqueue(503, { "error" => "vocabulary_unavailable" }) }
    err = assert_raises(ApiError) { @client.vocabulary }
    assert_equal 503, err.status
    assert_equal 5, @stub.requests.size
  end

  def test_health_200
    @stub.enqueue(200, { "ok" => true, "store_writable" => true, "pending" => 0, "dead" => 0,
                         "oldest_pending_age_s" => nil })
    h = @client.health
    assert h.ok
    assert h.store_writable
    assert_equal 0, h.pending
    assert_nil h.oldest_pending_age_s
    assert_equal 200, h.http_status
    assert_nil @stub.requests.fetch(0).headers["x-api-key"]
  end

  def test_health_503_is_a_report_not_an_exception
    @stub.enqueue(503, { "ok" => false, "store_writable" => false, "pending" => 3, "dead" => 1,
                         "oldest_pending_age_s" => 120 })
    h = @client.health
    refute h.ok
    refute h.store_writable
    assert_equal 503, h.http_status
    assert_equal 1, @stub.requests.size
    assert_empty @sleeper.calls
  end

  # --- non-JSON bodies -----------------------------------------------------

  def test_non_json_error_body_still_yields_an_api_error
    @stub.enqueue(502, "<html>bad gateway</html>")
    @stub.enqueue(202, accepted_body)
    res = @client.submit_lead(sample_lead, idempotency_key: "acme:1")
    assert res.accepted?
    client = Client.new(api_key: TEST_KEY, base_url: @stub.url, sleeper: @sleeper, retry_policy: RetryPolicy.none)
    @stub.enqueue(502, "<html>bad gateway</html>")
    err = assert_raises(ApiError) { client.submit_lead(sample_lead, idempotency_key: "acme:1") }
    assert_equal "http_502", err.code
    assert_includes err.body, "bad gateway"
  end
end
