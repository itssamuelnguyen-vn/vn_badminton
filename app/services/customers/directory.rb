module Customers
  # The customer list of the owner's area. A customer is a phone number: everyone who booked
  # (online or through the owner) and every customer account, merged on the phone number.
  #
  #   Customers::Directory.new(query: "0901").entries  # => [Entry, ...] most recent booking first
  #   Customers::Directory.new.find("+84901234567")    # => Entry or nil
  class Directory
    LIMIT = 100

    Entry = Data.define(:phone, :name, :user, :bookings_count, :upcoming_count, :no_shows, :self_cancellations,
                        :revenue_vnd, :last_booking_at, :profile) do
      def blocked? = profile&.blocked? || false

      # URLs use the local form: /admin/customers/0901234567
      def to_param = PhoneNumber.local_digits(phone)
    end

    def initialize(query: nil, now: Time.current)
      @query = query.to_s.strip
      @now = now
    end

    def entries
      stats = booking_stats(filtered_bookings).index_by { |row| row["phone"] }
      users = filtered_users.index_by(&:phone)
      phones = (stats.keys + users.keys).uniq
      profiles = CustomerProfile.where(phone: phones).index_by(&:phone)

      phones.map { |phone| build(phone, stats[phone], users[phone], profiles[phone]) }
            .sort_by { |entry| [ entry.last_booking_at ? 0 : 1, -(entry.last_booking_at&.to_i || 0), entry.name.to_s ] }
            .first(LIMIT)
    end

    def find(phone)
      phone = PhoneNumber.normalize(phone)
      return unless phone.to_s.match?(PhoneNumber::FORMAT)

      stats = booking_stats(reservations.where(customer_phone: phone)).first
      user = User.customer.find_by(phone: phone) || User.find_by(phone: phone)
      return if stats.nil? && user.nil?

      build(phone, stats, user, CustomerProfile.find_by(phone: phone))
    end

    private

    # Those of deleted accounts have no phone any more (Accounts::Deletion).
    def reservations
      Booking.kind_reservation.where.not(status: :pending).where.not(customer_phone: nil)
    end

    def filtered_bookings
      return reservations if @query.empty?

      if (digits = phone_digits)
        reservations.where("customer_phone LIKE ?", "%#{digits}%")
      else
        reservations.where("customer_name ILIKE ?", "%#{Booking.sanitize_sql_like(@query)}%")
      end
    end

    def filtered_users
      users = User.customer.where.not(phone: nil)
      return users if @query.empty?

      if (digits = phone_digits)
        users.where("phone LIKE ?", "%#{digits}%")
      else
        pattern = "%#{User.sanitize_sql_like(@query)}%"
        users.where("full_name ILIKE :q OR email ILIKE :q", q: pattern)
      end
    end

    # "0901 234" -> "901234" (stored numbers are +84901234567, so the leading 0 is dropped).
    def phone_digits
      digits = @query.gsub(/[\s.+-]/, "")
      return unless digits.match?(/\A\d{3,}\z/)

      digits.sub(/\A(84|0)/, "")
    end

    def booking_stats(scope)
      scope.group(:customer_phone).pluck(Arel.sql(<<~SQL)).map { |row| STATS_COLUMNS.zip(row).to_h }
        customer_phone,
        (array_agg(customer_name ORDER BY created_at DESC))[1],
        count(*),
        count(*) FILTER (WHERE status IN ('confirmed', 'checked_in') AND ends_at > #{Booking.connection.quote(@now)}),
        count(*) FILTER (WHERE status = 'no_show'),
        count(*) FILTER (WHERE status = 'cancelled' AND cancelled_by_id = user_id),
        coalesce(sum(total_amount_vnd) FILTER (WHERE status IN ('confirmed', 'checked_in', 'completed')), 0),
        max(starts_at)
      SQL
    end

    STATS_COLUMNS = %w[phone name count upcoming no_shows self_cancellations revenue last_at].freeze

    def build(phone, stats, user, profile)
      Entry.new(phone: phone, name: stats&.dig("name") || user&.full_name, user: user,
                bookings_count: stats&.dig("count") || 0, upcoming_count: stats&.dig("upcoming") || 0,
                no_shows: stats&.dig("no_shows") || 0, self_cancellations: stats&.dig("self_cancellations") || 0,
                revenue_vnd: stats&.dig("revenue").to_i, last_booking_at: stats&.dig("last_at"), profile: profile)
    end
  end
end
