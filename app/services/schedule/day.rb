module Schedule
  # The booking grid of the venue for one local date: every 30-minute slot of every active court,
  # with its state and price.
  #
  #   day = Schedule::Day.new(venue: Venue.main, date: Date.new(2026, 10, 20), user: current_user)
  #   day.times                      # => slot start times from opening to closing
  #   day.slot(court, time).state    # => :available, :booked, :mine, :blocked or :unavailable
  class Day
    SLOT = 30.minutes

    Slot = Data.define(:court, :starts_at, :state, :price_vnd) do
      def ends_at = starts_at + SLOT
      def available? = state == :available
    end

    attr_reader :venue, :date, :courts

    def initialize(venue:, date:, user: nil, now: Time.current)
      @venue = venue
      @date = date
      @user = user
      @now = now
      @courts = venue.courts.active.to_a
      @rule_set = Pricing::RuleSet.new(venue)
    end

    def opening
      @opening ||= venue.opening_hour_for(date)
    end

    def open?
      opening.present?
    end

    def times
      return [] unless open?

      day_start = venue.zone.local(date.year, date.month, date.day)
      (opening.opens_minute...opening.closes_minute).step(SLOT / 60).map { |minute| day_start + minute.minutes }
    end

    def slot(court, starts_at)
      price = @rule_set.rule_for(court: court, slot_start: starts_at)&.price_per_slot_vnd
      Slot.new(court: court, starts_at: starts_at, state: state_of(court, starts_at, price), price_vnd: price)
    end

    private

    def state_of(court, starts_at, price)
      booking = bookings_by_court[court.id]&.find { |b| b.starts_at < starts_at + SLOT && b.ends_at > starts_at }

      if booking
        return :blocked if booking.kind_block?

        @user && booking.user_id == @user.id ? :mine : :booked
      elsif starts_at < @now || price.nil? # already started, or no price rule covers it
        :unavailable
      else
        :available
      end
    end

    def bookings_by_court
      @bookings_by_court ||= Booking.holding_slot
                                    .where(court: courts)
                                    .on_local_date(date, venue.zone)
                                    .group_by(&:court_id)
    end
  end
end
