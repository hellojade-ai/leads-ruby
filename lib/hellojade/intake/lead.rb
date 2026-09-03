# frozen_string_literal: true

require "json"

module Hellojade
  module Intake
    # One lead, in the API's envelope. +first_name+, +last_name+ and +phone+
    # are required; everything else is optional and omitted from the JSON when
    # nil. Fields the API does not model go in +extra+ and are sent at the top
    # level, where the API preserves them (rule 7).
    class Lead
      FIELDS = %i[
        first_name last_name phone email street_address city state zip country
        project_area project_service project_material project_details
        external_id cost
      ].freeze

      # The closed project_service enum. project_area is NOT a constant on
      # purpose — fetch it with Client#vocabulary.
      PROJECT_SERVICES = %w[replacement repair remodel maintain].freeze

      # Keys a partner must never send at the top level. "source" comes from
      # the API key (rule 6); "extra" is reserved by the API.
      RESERVED_KEYS = %w[source extra].freeze

      attr_accessor(*FIELDS)
      attr_reader :extra

      def initialize(first_name:, last_name:, phone:, extra: {}, **rest)
        unknown = rest.keys - FIELDS
        unless unknown.empty?
          raise ArgumentError,
                "unknown lead field(s): #{unknown.join(', ')} — pass unmodeled fields as extra: {...}"
        end

        @first_name = first_name
        @last_name = last_name
        @phone = phone
        rest.each { |k, v| public_send("#{k}=", v) }
        self.extra = extra
      end

      def extra=(hash)
        hash = (hash || {}).transform_keys(&:to_s)
        reserved = hash.keys & RESERVED_KEYS
        unless reserved.empty?
          raise ArgumentError, "reserved key(s) in extra: #{reserved.join(', ')} — " \
                               "source comes from your API key and extra is set by the API"
        end
        collide = hash.keys & FIELDS.map(&:to_s)
        raise ArgumentError, "extra collides with modeled field(s): #{collide.join(', ')}" unless collide.empty?

        @extra = hash
      end

      # The JSON object the API receives. Modeled fields with a nil value are
      # omitted — never sent as null or as a placeholder (rule 1).
      def to_h
        out = {}
        @extra.each { |k, v| out[k] = v }
        FIELDS.each do |f|
          v = public_send(f)
          out[f.to_s] = v unless v.nil?
        end
        out
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      # Build a Lead from a Hash (string or symbol keys). Unmodeled keys land
      # in +extra+.
      def self.from_h(hash)
        h = hash.transform_keys(&:to_sym)
        extra = h.reject { |k, _| FIELDS.include?(k) }.transform_keys(&:to_s)
        modeled = h.select { |k, _| FIELDS.include?(k) }
        new(**modeled, extra: extra)
      end
    end
  end
end
