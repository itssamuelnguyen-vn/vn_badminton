module Schedule
  # The owner's view of one local date: every booking and block on every active court, laid out on
  # 30-minute rows. Rows cover the opening hours, widened to fit bookings made outside of them.
  #
  #   board = Schedule::Board.new(venue: Venue.main, date: Date.new(2026, 10, 20))
  #   board.times                 # => slot start times, one per row
  #   board.placements            # => where each booking sits on the grid (column and rows)
  #   board.free?(court, time)    # => true when nothing holds that slot
  class Board
    SLOT = 30.minutes

    Placement = Data.define(:booking, :column, :first_row, :last_row)

    attr_reader :venue, :date, :courts

    def initialize(venue:, date:)
      @venue = venue
      @date = date
      @courts = venue.courts.active.to_a
    end

    def opening
      @opening ||= venue.opening_hour_for(date)
    end

    def open?
      opening.present?
    end

    # Every booking of the day (cancelled ones included), in time order.
    def bookings
      @bookings ||= Booking.where(court: courts)
                           .on_local_date(date, venue.zone)
                           .includes(:court, :user, :items)
                           .order(:starts_at, :court_id)
                           .to_a
    end

    def active_bookings
      bookings.select(&:holds_slot?)
    end

    def reservations
      active_bookings.select(&:kind_reservation?)
    end

    def cancelled_bookings
      bookings.select(&:cancelled?)
    end

    def times
      @times ||= begin
        first, last = minute_range
        first ? (first...last).step(SLOT / 60).map { |minute| day_start + minute.minutes } : []
      end
    end

    # Bookings that run past midnight are cut at the edges of the day.
    def placements
      @placements ||= active_bookings.filter_map do |booking|
        column = courts.index { |court| court.id == booking.court_id }
        first = row_of([ booking.starts_at, times.first ].max)
        last = row_of([ booking.ends_at, times.last + SLOT ].min)
        Placement.new(booking: booking, column: column, first_row: first, last_row: last) if column && first && last && last > first
      end
    end

    def free?(court, starts_at)
      active_bookings.none? { |b| b.court_id == court.id && b.starts_at < starts_at + SLOT && b.ends_at > starts_at }
    end

    def expected_vnd
      reservations.sum(&:charged_vnd)
    end

    def collected_vnd
      reservations.select(&:payment_paid?).sum(&:charged_vnd)
    end

    def day_start
      @day_start ||= venue.zone.local(date.year, date.month, date.day)
    end

    private

    # Row index of a slot boundary (0 = top of the first row).
    def row_of(time)
      ((time - times.first) / SLOT).round if times.any?
    end

    def minute_range
      minutes = active_bookings.flat_map do |booking|
        [ [ ((booking.starts_at - day_start) / 60).to_i, 0 ].max, [ ((booking.ends_at - day_start) / 60).to_i, 1440 ].min ]
      end
      minutes += [ opening.opens_minute, opening.closes_minute ] if open?
      [ minutes.min, minutes.max ]
    end
  end
end
