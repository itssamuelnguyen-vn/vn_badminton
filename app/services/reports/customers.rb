module Reports
  # The owner's customer report, for a month or the last few months up to it. Customers are phone numbers
  # (as in Customers::Directory); reservations only, holds excluded.
  #
  #   report = Reports::Customers.new(venue: Venue.main, month: Date.new(2026, 10, 1), months: 3)
  #   report.top_by_hours    # => [Row, ...] most court time played in the period first
  #   report.top_by_amount   # => [Row, ...] most money first
  #   report.lapsed          # => [Lapsed, ...] regulars who stopped booking (as of now, not of the period)
  #
  # Played: not cancelled (Booking::PLAYED_STATUSES; no-shows are no longer recorded, older ones are left out).
  # Amount: what the customer pays (court less discount, plus products) for the bookings not cancelled,
  # older no-shows included, as the monthly report's expected revenue (Reports::Month).
  class Customers
    PERIODS = [ 1, 3, 6, 12 ].freeze
    TOP = 10
    LIMIT = 50
    # A regular gone quiet: played at least LAPSED_MIN_VISITS times, nothing booked for LAPSED_AFTER.
    LAPSED_MIN_VISITS = 3
    LAPSED_AFTER = 30.days
    PLAYED_SQL = "status IN (#{Booking::PLAYED_STATUSES.map { |status| "'#{status}'" }.join(", ")})"
    COUNTED_SQL = "status IN ('confirmed', 'checked_in', 'completed', 'no_show')"

    Row = Data.define(:phone, :name, :played, :minutes, :amount_vnd, :profile) do
      def blocked? = profile&.blocked? || false
      # URLs use the local form: /admin/customers/0901234567
      def to_param = PhoneNumber.local_digits(phone)
    end
    Lapsed = Data.define(:phone, :name, :visits, :last_visit_at, :profile) do
      def blocked? = profile&.blocked? || false
      def to_param = PhoneNumber.local_digits(phone)
    end

    attr_reader :venue, :month, :months, :now

    def initialize(venue:, month:, months: 1, now: Time.current)
      @venue = venue
      @month = month.beginning_of_month
      @months = PERIODS.include?(months) ? months : 1
      @now = now
    end

    # The first month of the period.
    def first_month
      month << (months - 1)
    end

    def top_by_hours
      rows.select { |row| row.minutes.positive? }.sort_by { |row| [ -row.minutes, -row.amount_vnd ] }.first(TOP)
    end

    def top_by_amount
      rows.select { |row| row.amount_vnd.positive? }.sort_by { |row| [ -row.amount_vnd, -row.minutes ] }.first(TOP)
    end


    # Most recently seen first: the easiest to win back.
    def lapsed
      @lapsed ||= begin
        regulars_gone_quiet = <<~SQL
          count(*) FILTER (WHERE #{PLAYED_SQL} AND starts_at < #{Booking.connection.quote(now)}) >= #{LAPSED_MIN_VISITS}
          AND max(starts_at) FILTER (WHERE status <> 'cancelled') <= #{Booking.connection.quote(now - LAPSED_AFTER)}
        SQL
        columns = <<~SQL
          customer_phone,
          (array_agg(customer_name ORDER BY starts_at DESC))[1],
          count(*) FILTER (WHERE #{PLAYED_SQL} AND starts_at < #{Booking.connection.quote(now)}),
          max(starts_at) FILTER (WHERE #{PLAYED_SQL})
        SQL
        list = reservations.group(:customer_phone).having(Arel.sql(regulars_gone_quiet))
                           .order(Arel.sql("max(starts_at) FILTER (WHERE #{PLAYED_SQL}) DESC")).limit(LIMIT).pluck(Arel.sql(columns))
        profiles = profiles(list.map(&:first))
        list.map do |phone, name, visits, last|
          Lapsed.new(phone: phone, name: name, visits: visits, last_visit_at: last.in_time_zone(venue.zone), profile: profiles[phone])
        end
      end
    end

    private

    # Those of deleted accounts have no phone any more (Accounts::Deletion).
    def reservations
      Booking.kind_reservation.where.not(status: :pending).where.not(customer_phone: nil)
    end

    def range
      from = venue.zone.local(first_month.year, first_month.month, 1)
      from...venue.zone.local(month.next_month.year, month.next_month.month, 1)
    end

    # One row per customer who booked in the period, from a single grouped query.
    def rows
      @rows ||= begin
        list = reservations.where(starts_at: range).group(:customer_phone).pluck(Arel.sql(<<~SQL))
          customer_phone,
          (array_agg(customer_name ORDER BY starts_at DESC))[1],
          count(*) FILTER (WHERE #{PLAYED_SQL}),
          coalesce(sum(extract(epoch FROM ends_at - starts_at)::integer / 60) FILTER (WHERE #{PLAYED_SQL}), 0),
          coalesce(sum(total_amount_vnd - discount_vnd + items_amount_vnd) FILTER (WHERE #{COUNTED_SQL}), 0)
        SQL
        profiles = profiles(list.map(&:first))
        list.map do |phone, name, played_count, minutes, amount|
          Row.new(phone: phone, name: name, played: played_count, minutes: minutes.to_i, amount_vnd: amount.to_i, profile: profiles[phone])
        end
      end
    end

    # The profiles (blacklist) of the customers listed, in one query.
    def profiles(phones)
      CustomerProfile.where(phone: phones).index_by(&:phone)
    end
  end
end
