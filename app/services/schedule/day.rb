module Schedule
  # The booking grid of the venue for one local date: every 30-minute slot of every active court,
  # with its state and price.
  #
  #   day = Schedule::Day.new(venue: Venue.main, date: Date.new(2026, 10, 20), user: current_user)
  #   day.times                      # => slot start times from opening to closing
  #   day.upcoming_times             # => the same without slots that already started (today)
  #   day.slot(court, time).state    # => :available, :booked, :held, :mine, :blocked or :unavailable
  class Day
    SLOT = 30.minutes

    Slot = Data.define(:court, :starts_at, :state, :price_vnd) do
      def ends_at = starts_at + SLOT
      def available? = state == :available
    end

    attr_reader :venue, :date, :courts

    # ignore: a booking being moved (reschedule mode), whose own slots can be picked again.
    def initialize(venue:, date:, user: nil, now: Time.current, ignore: nil)
      @venue = venue
      @date = date
      @user = user
      @now = now
      @ignore = ignore
      @courts = venue.courts.active.to_a
      @rule_set = Pricing::RuleSet.new(venue)
    end

    def opening
      @opening ||= venue.opening_hour_for(date)
    end

    def open?
      opening.present?
    end

    # False once every slot of the day has started (e.g. today after closing time).
    def bookable?
      upcoming_times.any?
    end

    # The rows the customer schedule shows: on today's date, slots that already started cannot be booked,
    # so they are left out instead of making customers scroll past them.
    def upcoming_times
      times.select { |time| time >= @now }
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
        return :held if booking.pending? # another customer is on the confirmation page

        @user && booking.user_id == @user.id ? :mine : :booked
      elsif starts_at < @now || price.nil? # already started, or no price rule covers it
        :unavailable
      else
        :available
      end
    end

    def bookings_by_court
      # The customer's own hold is left out: those slots stay selectable for them (picking again replaces it).
      @bookings_by_court ||= Booking.holding_slot(@now)
                                    .where(court: courts)
                                    .on_local_date(date, venue.zone)
                                    .reject { |b| (b.pending? && @user && b.user_id == @user.id) || b.id == @ignore&.id }
                                    .group_by(&:court_id)
    end
  end
end
