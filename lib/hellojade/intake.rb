# frozen_string_literal: true

require_relative "intake/version"
require_relative "intake/errors"
require_relative "intake/lead"
require_relative "intake/responses"
require_relative "intake/retry_policy"
require_relative "intake/client"

module Hellojade
  # Ruby client for the hellojade Partner Intake API.
  # https://intake.hellojade.ai/api
  module Intake
    # Shorthand for Client.new(**options).
    def self.new(**options)
      Client.new(**options)
    end
  end
end
