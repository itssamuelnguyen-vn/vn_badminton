require "test_helper"

# The busy pages load a day's bookings with one query and build the grid in memory: the number of queries
# must not grow with the number of bookings (no N+1).
class QueryCountsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
  end

  test "the booking page, the day board, the customer's bookings and packages do not query per booking" do
    pages = {
      users(:an) => [ root_path(date: "2026-10-20"), bookings_path, packages_path ],
      users(:staffer) => [ root_path(date: "2026-10-20"), admin_root_path(date: "2026-10-20") ],
      users(:owner) => [ admin_bank_transactions_path, admin_customers_path, admin_customer_reports_path(month: "2026-10", months: 3) ]
    }

    add_bookings(5) # with none, the preloading queries (includes) would not run at all
    few = query_counts(pages)
    add_bookings(30, from: 5)
    many = query_counts(pages)

    assert_equal few, many
  end

  test "the cash shift pages do not query per cash payment" do
    Current.user = users(:staffer)
    shift = CashShift.open!(venue: venues(:phu_nhuan), by: users(:staffer), opening_vnd: 0)
    pages = { users(:owner) => [ admin_cash_shifts_path, admin_cash_shift_path(shift) ] }

    add_bookings(5)
    Booking.find_each { |booking| booking.mark_paid! if booking.confirmed? }
    few = query_counts(pages)
    add_bookings(30, from: 5)
    Booking.find_each { |booking| booking.mark_paid! if booking.confirmed? && booking.payment_unpaid? }
    many = query_counts(pages)

    assert_equal few, many
    assert_operator shift.events.count, :>, 15
  ensure
    Current.reset
  end

  private

  def query_counts(pages)
    pages.flat_map do |user, paths|
      reset!
      sign_in user
      paths.map do |path|
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" } # cached ones too: still a query per booking
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path }
        assert_response :success
        [ "#{user.email} #{path}", count ]
      end
    end.to_h
  end

  # Half-hour bookings spread over every court of 2026-10-20, alternating users(:an) and users(:chi); two in
  # every five are holds (one per court). Booked by phone, so the online minimum duration does not apply.
  def add_bookings(count, from: 0)
    courts = Court.active.to_a
    (from...from + count).each do |i|
      starts_at = Time.zone.parse("2026-10-20 06:00") + (i / courts.size) * 30.minutes
      courts[i % courts.size].bookings.create!(
        user: i.even? ? users(:an) : users(:chi), source: :phone, starts_at: starts_at, ends_at: starts_at + 30.minutes,
        status: i % 5 < 2 ? :pending : :confirmed, expires_at: (10.minutes.from_now if i % 5 < 2)
      )
    end
  end
end
