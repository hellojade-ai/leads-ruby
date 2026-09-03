# frozen_string_literal: true

# Submit one lead with the full envelope, and handle every outcome.
#
#   HELLOJADE_API_KEY=... ruby -Ilib examples/submit_lead.rb
#
# Do NOT run this against production with a real-looking name and phone unless
# hellojade has issued you a sandbox key: a real lead reaches a real salesperson.

require "hellojade/intake"

client = Hellojade::Intake::Client.new(
  api_key: ENV.fetch("HELLOJADE_API_KEY"),
  base_url: ENV.fetch("HELLOJADE_BASE_URL", "https://intake.hellojade.ai"),
  timeout: 20,
  user_agent: "acme-leads-sync/2.3"
)

# Your own record id. It becomes the Idempotency-Key (namespaced) and external_id.
lead_id = "A-99812"

lead = Hellojade::Intake::Lead.new(
  first_name: "Dana",
  last_name: "Whitfield",
  phone: "(630) 555-0142",
  email: "dana.whitfield@example.com",
  street_address: "418 N Maple St",
  city: "Naperville",
  state: "IL",
  zip: "60540",
  country: "US",
  project_area: "roof",            # fetch the live list with client.vocabulary
  project_service: "replacement",  # replacement | repair | remodel | maintain
  project_material: "asphalt shingle",
  project_details: "Hail damage on the south slope, insurance claim already filed.",
  external_id: lead_id,
  cost: 555.55,                    # omit entirely if there is no charge; never 0
  extra: { "partner_job_id" => "XZ-1" } # unmodeled fields are preserved, not rejected
)

begin
  result = client.submit_lead(lead, idempotency_key: "acme-leads:#{lead_id}", request_id: "acme-leads/#{lead_id}")
  # 202 => "accepted", 200 => "duplicate" (same event_id as the first time). Both are success.
  puts "#{result.status}: event_id=#{result.event_id} source=#{result.source}"
  puts "flags (not errors): #{result.flags.join(', ')}" unless result.flags.empty?
rescue Hellojade::Intake::ValidationError => e
  # 422 — every failing field at once. Fix the body; do not retry it unchanged.
  warn "validation failed (request_id=#{e.request_id}): #{e.fields.inspect}"
rescue Hellojade::Intake::Unauthorized => e
  warn "unauthorized (request_id=#{e.request_id}) — this is a configuration problem, not a retry"
rescue Hellojade::Intake::RateLimited => e
  warn "rate limited for too long (last Retry-After=#{e.retry_after}s)"
rescue Hellojade::Intake::ApiError => e
  # 400 / 413 / exhausted 5xx. Keep request_id — it is the handle support needs.
  warn "intake error #{e.status} #{e.code} (request_id=#{e.request_id})"
rescue Hellojade::Intake::TransportError => e
  warn "no response after #{e.attempts} attempts: #{e.message}"
end
