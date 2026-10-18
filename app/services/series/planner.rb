module Series
  # The sessions of a series between two dates, each checked like a booking made by the venue: free court,
  # opening hours, a price. The preview shows which sessions can be created; #create! creates those.
  #
  #   plan = Series::Planner.new(series, from: series.starts_on, to: series.ends_on, by: owner)
  #   plan.sessions   # => [Session(court, starts_at, ends_at, booking, errors), ...]
  #   plan.create!    # => the sessions saved (others skipped, e.g. taken meanwhile)
  class Planner
    Session = Data.define(:court, :starts_at, :ends_at, :booking) do
      def ok? = booking.errors.empty?
      def problems = booking.errors.full_messages
    end

    def initialize(series, from:, to:, by:)
      @series = series
      @from = from
      @to = to
      @by = by
    end

    def sessions
      @sessions ||= @series.slots(@series.dates(from: @from, to: @to)).map do |court, starts_at, ends_at|
        booking = build(court, starts_at, ends_at)
        booking.validate
        Session.new(court: court, starts_at: starts_at, ends_at: ends_at, booking: booking)
      end
    end

    def ok
      sessions.select(&:ok?)
    end

    def total_vnd
      ok.sum { |session| session.booking.total_amount_vnd }
    end

    # Saves the series (when new) and the sessions that were free; each one through Booking#reserve,
    # so a slot taken since the preview is skipped. Returns the bookings created.
    def create!
      BookingSeries.transaction do
        @series.save! if @series.new_record?
        ok.filter_map do |session|
          booking = build(session.court, session.starts_at, session.ends_at)
          booking if booking.reserve
        end
      end
    end

    private

    def build(court, starts_at, ends_at)
      Booking.new(court: court, series: @series, user: @series.user, source: :phone, created_by: @by,
                  customer_name: @series.customer_name, customer_phone: @series.customer_phone,
                  starts_at: starts_at, ends_at: ends_at, note: @series.note).tap { |b| b.staff_change = true }
    end
  end
end
