module Pricing
  # Prices a time range on a court, one 30-minute slot at a time.
  #
  #   result = Pricing::Quote.new(court:, starts_at:, ends_at:).call
  #   result.total_vnd  # => 180000
  #   result.breakdown  # => [{ "from" => "...", "to" => "...", "price_rule_id" => 3, "amount_vnd" => 180000 }]
  class Quote
    SLOT = 30.minutes

    class NoPriceError < StandardError
      attr_reader :slot_start

      def initialize(slot_start)
        @slot_start = slot_start
        super("No price rule covers the slot starting at #{slot_start.iso8601}")
      end
    end

    Result = Data.define(:total_vnd, :breakdown)

    def initialize(court:, starts_at:, ends_at:)
      @court = court
      @starts_at = starts_at
      @ends_at = ends_at
    end

    def call
      zone = @court.venue.zone
      rules = ordered_rules
      segments = []

      slot_start = @starts_at
      while slot_start < @ends_at
        local = slot_start.in_time_zone(zone)
        rule = rules.find { |r| r.applies_to?(court: @court, local_slot_start: local) }
        raise NoPriceError.new(slot_start) unless rule

        add_slot(segments, slot_start, rule)
        slot_start += SLOT
      end

      Result.new(total_vnd: segments.sum { |s| s["amount_vnd"] }, breakdown: segments)
    end

    private

    # Court-specific rules first, then higher priority, then the most recently created rule.
    def ordered_rules
      @court.venue.price_rules.active.where(court_id: [ nil, @court.id ]).to_a
            .sort_by { |r| [ r.court_id ? 0 : 1, -r.priority, -r.id ] }
    end

    # Merge consecutive slots priced by the same rule into one line.
    def add_slot(segments, slot_start, rule)
      last = segments.last
      if last && last["price_rule_id"] == rule.id
        last["to"] = (slot_start + SLOT).iso8601
        last["amount_vnd"] += rule.price_per_slot_vnd
      else
        segments << {
          "from" => slot_start.iso8601,
          "to" => (slot_start + SLOT).iso8601,
          "price_rule_id" => rule.id,
          "price_per_hour_vnd" => rule.price_per_hour_vnd,
          "amount_vnd" => rule.price_per_slot_vnd
        }
      end
    end
  end
end
