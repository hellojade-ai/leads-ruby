# frozen_string_literal: true

# Prove your key works without creating a lead.
#
#   HELLOJADE_API_KEY=... ruby -Ilib examples/check_key.rb
#
# The API authenticates before it validates, so an empty body with a valid key
# is rejected with 422 — and nothing is stored, delivered or emailed.

require "hellojade/intake"

client = Hellojade::Intake::Client.new(api_key: ENV.fetch("HELLOJADE_API_KEY"))

if client.check_key
  puts "key is valid and active (API answered 422 to an empty body; nothing stored)"
else
  puts "key rejected (401): check the X-API-Key value for whitespace, then ask hellojade whether it is active"
  exit 1
end
