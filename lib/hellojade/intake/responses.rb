# frozen_string_literal: true

module Hellojade
  module Intake
    # The body of a 202 (status "accepted") or a 200 (status "duplicate").
    # Both are success. +flags+ is always an Array and flags are never errors
    # (rule 8). +source+ is the label of the API key that submitted the lead.
    Accepted = Struct.new(:event_id, :status, :received_at, :flags, :source, :request_id, :http_status,
                          keyword_init: true) do
      def accepted?
        status == "accepted"
      end

      def duplicate?
        status == "duplicate"
      end

      def self.from_response(http_status, body, request_id)
        new(
          event_id: body["event_id"],
          status: body["status"],
          received_at: body["received_at"],
          flags: Array(body["flags"]),
          source: body["source"],
          request_id: request_id,
          http_status: http_status
        )
      end
    end

    # One accepted project_area term. +status+ is "confirmed" or "proposed";
    # both are accepted by the API.
    VocabularyTerm = Struct.new(:area, :status, keyword_init: true)

    # GET /v1/vocabulary — the live project_area terms, the closed
    # project_service enum, and the fields the validator currently requires.
    Vocabulary = Struct.new(:project_area, :project_service, :required, keyword_init: true) do
      def self.from_body(body)
        new(
          project_area: Array(body["project_area"]).map do |t|
            VocabularyTerm.new(area: t["area"], status: t["status"])
          end,
          project_service: Array(body["project_service"]),
          required: Array(body["required"])
        )
      end

      def areas
        project_area.map(&:area)
      end

      def area?(term)
        areas.include?(term)
      end
    end

    # GET /healthz. Returned for both 200 and 503 — a 503 is a report, not a
    # failure of the call.
    Health = Struct.new(:ok, :store_writable, :pending, :dead, :oldest_pending_age_s, :http_status,
                        keyword_init: true) do
      def self.from_response(http_status, body)
        new(
          ok: body["ok"] == true,
          store_writable: body["store_writable"] == true,
          pending: body["pending"],
          dead: body["dead"],
          oldest_pending_age_s: body["oldest_pending_age_s"],
          http_status: http_status
        )
      end
    end
  end
end
