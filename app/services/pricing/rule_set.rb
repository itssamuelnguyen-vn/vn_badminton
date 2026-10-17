module Pricing
  # The active price rules of a venue, loaded once, answering "which rule prices this slot on this court?".
  # Court-specific rules win over venue-wide ones, then higher priority, then the most recently created rule.
  class RuleSet
    def initialize(venue)
      @zone = venue.zone
      @rules = venue.price_rules.active.to_a.sort_by { |r| [ r.court_id ? 0 : 1, -r.priority, -r.id ] }
    end

    def rule_for(court:, slot_start:)
      local = slot_start.in_time_zone(@zone)
      @rules.find { |r| r.applies_to?(court: court, local_slot_start: local) }
    end
  end
end
