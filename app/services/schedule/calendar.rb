module Schedule
  # The month calendar used to pick a day on the schedule. A date is selectable when it is
  # within the booking horizon, the venue opens that day, and (for today) a slot is still to come.
  #
  #   calendar = Schedule::Calendar.new(venue: Venue.main, selected: date)
  #   calendar.months          # => first day of each month the bookable dates fall in
  #   calendar.weeks(month)    # => weeks of 7 dates, Monday first, padded with the neighbouring months
  #   calendar.selectable?(d)  # => false for past days, closed days, days beyond the horizon
  class Calendar
    attr_reader :venue, :selected

    def initialize(venue:, selected:, now: Time.current)
      @venue = venue
      @selected = selected
      @now = now
    end

    def selectable?(date)
      selectable_dates.include?(date)
    end

    def first_selectable
      selectable_dates.first
    end

    def previous_selectable
      selectable_dates.reverse.find { |date| date < selected }
    end

    def next_selectable
      selectable_dates.find { |date| date > selected }
    end

    def months
      venue.bookable_dates.map(&:beginning_of_month).uniq
    end

    def weeks(month)
      first = month.beginning_of_month.beginning_of_week(:monday)
      last = month.end_of_month.end_of_week(:monday)
      (first..last).each_slice(7).to_a
    end

    private

    def selectable_dates
      @selectable_dates ||= venue.bookable_dates.select do |date|
        venue.opening_hour_for(date) && (date != venue.today || Day.new(venue: venue, date: date, now: @now).bookable?)
      end
    end
  end
end
