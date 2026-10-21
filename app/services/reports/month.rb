module Reports
  # The owner's monthly report: revenue and occupancy per day, and occupancy per hour of the day.
  #
  #   report = Reports::Month.new(venue: Venue.main, month: Date.new(2026, 10, 1))
  #   report.days        # => [Day, ...] one per date of the month
  #   report.totals      # => Day-like totals for the month
  #   report.hours       # => [Hour, ...] occupancy of each opening hour over the month
  #   report.weekdays    # => [[1, [Hour, ...]], ...] the same per day of the week, Monday first
  #
  # Occupancy = booked court-minutes / court-minutes open (opening hours x active courts).
  # Revenue counts reservations that were not cancelled (holds excluded); "collected" the paid ones.
  class Month
    COUNTED_STATUSES = %w[confirmed checked_in completed no_show].freeze

    Day = Data.define(:date, :bookings, :booked_minutes, :open_minutes, :expected_vnd, :collected_vnd, :no_shows, :cancelled) do
      def occupancy = open_minutes.zero? ? nil : booked_minutes.fdiv(open_minutes)
    end
    Hour = Data.define(:hour, :booked_minutes, :open_minutes) do
      def occupancy = open_minutes.zero? ? nil : booked_minutes.fdiv(open_minutes)
    end

    attr_reader :venue, :month

    def initialize(venue:, month:)
      @venue = venue
      @month = month.beginning_of_month
      @courts = venue.courts.active.count
    end

    def days
      @days ||= dates.map do |date|
        list = bookings_by_date.fetch(date, [])
        counted = list.select { |b| COUNTED_STATUSES.include?(b.status) }
        Day.new(date: date, bookings: counted.size, booked_minutes: counted.sum(&:duration_minutes),
                open_minutes: open_minutes(date), expected_vnd: counted.sum(&:charged_vnd),
                collected_vnd: counted.select(&:payment_paid?).sum(&:charged_vnd),
                no_shows: counted.count(&:no_show?), cancelled: list.count(&:cancelled?))
      end
    end

    def totals
      Day.new(date: nil, **%i[bookings booked_minutes open_minutes expected_vnd collected_vnd no_shows cancelled]
                             .to_h { |key| [ key, days.sum(&key) ] })
    end

    # Opening hours only; an hour that is open on some days counts on those days.
    def hours
      @hours ||= begin
        open, booked = minutes_by_weekday_and_hour
        open.keys.map(&:last).uniq.sort.map do |hour|
          Hour.new(hour: hour, booked_minutes: (0..6).sum { |wday| booked[[ wday, hour ]] },
                   open_minutes: (0..6).sum { |wday| open[[ wday, hour ]] })
        end
      end
    end

    # Rows for the weekday x hour heatmap, with the columns of #hours; a closed hour has open_minutes 0.
    def weekdays
      open, booked = minutes_by_weekday_and_hour
      [ 1, 2, 3, 4, 5, 6, 0 ].map do |wday|
        [ wday, hours.map { |h| Hour.new(hour: h.hour, booked_minutes: booked[[ wday, h.hour ]], open_minutes: open[[ wday, h.hour ]]) } ]
      end
    end

    # Prepaid hours sold in the month (paid then); the bookings paid with them count 0 in the revenue above.
    def packages_sold_vnd
      PackagePurchase.where.not(paid_at: nil).where(paid_at: range).sum(:price_vnd)
    end

    # Places sold in open play sessions held in the month (paid, less what is owed back).
    def tickets_sold_vnd
      tickets = PlaySessionTicket.joins(:play_session).where(play_sessions: { venue_id: venue.id, starts_at: range })
      tickets.where(status: :confirmed).sum(:amount_vnd)
    end

    # Every reservation of the month, for the CSV export.
    def reservations
      @reservations ||= Booking.kind_reservation.where.not(status: :pending)
                               .where(starts_at: range).includes(:court).joins(:court)
                               .order(:starts_at, "courts.position", "courts.id").to_a
    end

    private

    def dates
      month.all_month.to_a
    end

    def range
      venue.zone.local(month.year, month.month, 1)...venue.zone.local(month.next_month.year, month.next_month.month, 1)
    end

    # Court-minutes open and booked over the month, keyed by [wday, hour].
    def minutes_by_weekday_and_hour
      @minutes_by_weekday_and_hour ||= begin
        open = Hash.new(0)
        booked = Hash.new(0)
        dates.each do |date|
          opening = venue.opening_hour_for(date) or next
          (opening.opens_minute...opening.closes_minute).step(30) { |minute| open[[ date.wday, minute / 60 ]] += 30 * @courts }
        end
        reservations.select { |b| COUNTED_STATUSES.include?(b.status) }.each do |booking|
          local = booking.starts_at.in_time_zone(venue.zone)
          minute = local.hour * 60 + local.min
          booking.duration_minutes.step(1, -30) do
            booked[[ (local.to_date + minute.div(1440)).wday, (minute / 60) % 24 ]] += 30
            minute += 30
          end
        end
        [ open, booked ]
      end
    end

    def bookings_by_date
      @bookings_by_date ||= reservations.group_by { |b| b.starts_at.in_time_zone(venue.zone).to_date }
    end

    def open_minutes(date)
      opening = venue.opening_hour_for(date)
      opening ? (opening.closes_minute - opening.opens_minute) * @courts : 0
    end
  end
end
