module Loyalty
  # A customer's member tier: by the hours played in the last 12 months (bookings checked in or completed,
  # paid, regular sessions included). Bronze below silver. The thresholds and discounts are the venue's settings.
  #
  #   tier = Loyalty::Tier.for(user)
  #   tier.key        # => "gold"
  #   tier.percent    # => 5 (discount on online bookings' court price)
  #   tier.hours      # => 72.5
  #   tier.next       # => { key: "diamond", hours: 150 } or nil
  class Tier
    KEYS = %w[bronze silver gold diamond].freeze
    PERIOD = 12.months

    attr_reader :key, :hours, :venue

    def self.for(user, venue: Venue.main, now: Time.current)
      minutes = user.bookings.kind_reservation.where(status: %w[checked_in completed], payment_status: :paid)
                    .where(ends_at: (now - PERIOD)..now).sum("EXTRACT(EPOCH FROM (ends_at - starts_at)) / 60").to_i
      new(venue, minutes / 60.0)
    end

    def self.thresholds(venue)
      { "silver" => [ venue.silver_hours, venue.silver_percent ], "gold" => [ venue.gold_hours, venue.gold_percent ],
        "diamond" => [ venue.diamond_hours, venue.diamond_percent ] }
    end

    def initialize(venue, hours)
      @venue = venue
      @hours = hours
      @key = self.class.thresholds(venue).select { |_key, (threshold, _)| hours >= threshold }.keys.last || "bronze"
    end

    def percent
      return 0 unless venue.loyalty_enabled? && key != "bronze"

      self.class.thresholds(venue).fetch(key).last
    end

    def next
      key_index = KEYS.index(key)
      following = KEYS[key_index + 1] or return
      { key: following, hours: self.class.thresholds(venue).fetch(following).first }
    end

    def name
      I18n.t("loyalty.tiers.#{key}")
    end
  end
end
