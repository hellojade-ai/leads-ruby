# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/autorun"
require "socket"
require "hellojade/intake"
require_relative "stub_server"

# Records every requested sleep instead of sleeping.
class FakeSleeper
  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(seconds)
    @calls << seconds
  end
end

module StubClientTest
  TEST_KEY = "hj_test_key_do_not_log_5f3a9c"

  def setup
    @stub = StubServer.new
    @sleeper = FakeSleeper.new
    @client = Hellojade::Intake::Client.new(
      api_key: TEST_KEY, base_url: @stub.url, timeout: 2, sleeper: @sleeper,
      retry_policy: Hellojade::Intake::RetryPolicy.new(jitter: 0)
    )
  end

  def teardown
    @stub.stop
  end

  def accepted_body(status: "accepted", flags: [])
    { "event_id" => "evt_0198f2c1a4b00000a3d19f4c2b7e", "status" => status,
      "received_at" => "2026-08-21T14:03:22Z", "source" => "acme-leads", "flags" => flags }
  end

  def sample_lead
    Hellojade::Intake::Lead.new(
      first_name: "Dana", last_name: "Whitfield", phone: "(630) 555-0142",
      email: "dana.whitfield@example.com", city: "Naperville", state: "IL", zip: "60540",
      project_area: "roof", project_service: "replacement", external_id: "A-99812",
      extra: { "partner_job_id" => "XZ-1", "budget" => 25_000 }
    )
  end
end
