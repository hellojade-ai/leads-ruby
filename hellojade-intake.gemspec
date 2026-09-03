# frozen_string_literal: true

require_relative "lib/hellojade/intake/version"

Gem::Specification.new do |spec|
  spec.name = "hellojade-intake"
  spec.version = Hellojade::Intake::VERSION
  spec.authors = ["hellojade"]
  spec.email = ["developers@hellojade.ai"]
  spec.summary = "Ruby client for the hellojade Partner Intake API"
  spec.description = "Submit leads to https://intake.hellojade.ai with idempotency, " \
                     "Retry-After-aware retries, and typed errors. Net::HTTP only, no runtime dependencies."
  spec.homepage = "https://github.com/hellojade-ai/leads-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://intake.hellojade.ai/api"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
