# frozen_string_literal: true

require_relative "test_helper"

class LeadTest < Minitest::Test
  Lead = Hellojade::Intake::Lead

  def test_minimal_lead_serializes_only_required_fields
    lead = Lead.new(first_name: "Dana", last_name: "Whitfield", phone: "6305550142")
    assert_equal({ "first_name" => "Dana", "last_name" => "Whitfield", "phone" => "6305550142" }, lead.to_h)
  end

  def test_nil_fields_are_omitted_not_sent_as_null
    lead = Lead.new(first_name: "Dana", last_name: "Whitfield", phone: "1", email: nil, cost: nil)
    refute lead.to_h.key?("email")
    refute lead.to_h.key?("cost")
  end

  def test_extra_fields_are_sent_at_the_top_level
    lead = Lead.new(first_name: "Dana", last_name: "W", phone: "1", extra: { partner_job_id: "XZ-1", budget: 25_000 })
    h = JSON.parse(lead.to_json)
    assert_equal "XZ-1", h["partner_job_id"]
    assert_equal 25_000, h["budget"]
    refute h.key?("extra")
  end

  def test_modeled_field_wins_over_a_colliding_extra
    assert_raises(ArgumentError) { Lead.new(first_name: "D", last_name: "W", phone: "1", extra: { phone: "2" }) }
  end

  def test_source_and_extra_are_reserved
    assert_raises(ArgumentError) { Lead.new(first_name: "D", last_name: "W", phone: "1", extra: { source: "x" }) }
    assert_raises(ArgumentError) { Lead.new(first_name: "D", last_name: "W", phone: "1", extra: { extra: {} }) }
  end

  def test_unknown_keyword_is_rejected_with_guidance
    err = assert_raises(ArgumentError) { Lead.new(first_name: "D", last_name: "W", phone: "1", budget: 1) }
    assert_match(/extra/, err.message)
  end

  def test_required_fields_are_required
    assert_raises(ArgumentError) { Lead.new(first_name: "D", phone: "1") }
  end

  def test_from_h_routes_unmodeled_keys_to_extra
    lead = Lead.from_h("first_name" => "D", "last_name" => "W", "phone" => "1", "cost" => 12.5, "crew" => "north")
    assert_equal 12.5, lead.cost
    assert_equal({ "crew" => "north" }, lead.extra)
  end

  def test_project_services_enum
    assert_equal %w[replacement repair remodel maintain], Lead::PROJECT_SERVICES
  end
end
