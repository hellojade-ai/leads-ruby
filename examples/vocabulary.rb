# frozen_string_literal: true

# Print the live project_area vocabulary. Unauthenticated; no key needed.
#
#   ruby -Ilib examples/vocabulary.rb

require "hellojade/intake"

client = Hellojade::Intake::Client.new(api_key: ENV.fetch("HELLOJADE_API_KEY", "not-needed-for-vocabulary"))
vocab = client.vocabulary

puts "required: #{vocab.required.join(', ')}"
puts "project_service: #{vocab.project_service.join(', ')}"
puts "project_area:"
vocab.project_area.each { |t| puts "  #{t.area} (#{t.status})" }
