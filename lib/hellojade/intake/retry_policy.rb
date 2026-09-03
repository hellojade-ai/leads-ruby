# frozen_string_literal: true

module Hellojade
  module Intake
    # Rule 5: retry on 5xx, on transport errors, and on 429 after Retry-After.
    # Never on any other 4xx.
    #
    # * +max_attempts+ — delivery attempts. A 429 does not consume one.
    # * +max_rate_limit_waits+ — how many 429s to wait out before giving up.
    # * +base_delay+ / +max_delay+ — exponential backoff bounds, in seconds.
    # * +jitter+ — up to this many seconds of random extra delay, so a fleet
    #   of workers recovering from the same outage does not retry in lockstep.
    class RetryPolicy
      attr_reader :max_attempts, :max_rate_limit_waits, :base_delay, :max_delay, :jitter

      def initialize(max_attempts: 5, max_rate_limit_waits: 10, base_delay: 1.0, max_delay: 30.0, jitter: 0.5,
                     random: Random.new)
        raise ArgumentError, "max_attempts must be >= 1" if max_attempts < 1

        @max_attempts = max_attempts
        @max_rate_limit_waits = max_rate_limit_waits
        @base_delay = base_delay.to_f
        @max_delay = max_delay.to_f
        @jitter = jitter.to_f
        @random = random
      end

      # Seconds to wait before attempt n+1 (n starts at 1).
      def backoff(n)
        [base_delay * (2**(n - 1)), max_delay].min + (@random.rand * jitter)
      end

      # Seconds to wait after a 429: the server's Retry-After is a floor, not
      # a strategy, so the wait grows with each consecutive 429.
      def rate_limit_delay(retry_after, waits)
        [retry_after.to_f, backoff(waits)].max
      end

      # One attempt, no waiting. For callers that run their own retry loop.
      def self.none
        new(max_attempts: 1, max_rate_limit_waits: 0)
      end
    end
  end
end
