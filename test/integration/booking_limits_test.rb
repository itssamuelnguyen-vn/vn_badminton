require "test_helper"

class BookingLimitsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00") # Monday
    sign_in users(:an)
  end

  test "a customer holds at most 2 upcoming bookings" do
    book(:court_one, "2026-10-20 18:00")
    book(:court_one, "2026-10-21 18:00")

    assert_no_difference "Booking.count" do
      post bookings_path, params: { booking: { slots: { "0" => slot(:court_two, "2026-10-22 18:00", 60) } } }
    end
    assert_select "#error_explanation li", text: /Bạn đang có 2 lượt đặt sắp tới, là số tối đa/
  end

  test "cancelled and finished bookings do not count" do
    book(:court_one, "2026-10-20 18:00").cancel!(by: users(:an))
    travel_to(Time.zone.parse("2026-10-18 10:00")) { book(:court_one, "2026-10-18 18:00") }
    book(:court_one, "2026-10-21 18:00")

    assert_difference "Booking.count", 1 do
      post bookings_path, params: { booking: { slots: { "0" => slot(:court_two, "2026-10-22 18:00", 60) } } }
    end
  end

  test "several courts at once must fit in what is left" do
    book(:court_one, "2026-10-21 18:00")

    get new_booking_path(slots: { "0" => slot(:court_one, "2026-10-20 18:00", 60), "1" => slot(:court_two, "2026-10-20 18:00", 60) })

    assert_select "#error_explanation li", text: "Mỗi tài khoản giữ tối đa 2 lượt đặt sắp tới; bạn chỉ còn đặt thêm được 1 sân."
    assert_select "input[type=submit]", count: 0
    # Each card still shows its own price (not held, but priced), and can drop its court.
    assert_select "dd", text: "120.000đ", minimum: 2
    assert_select "dd", text: "0đ", count: 0
    remove = css_select("a[aria-label='Bỏ Sân 2 khỏi lần đặt này']").sole

    # Dropping court 2 opens the page again with court 1 alone, now within the limit and held.
    assert_difference("Booking.pending.count", 1) { get remove["href"] }
    assert_select "#error_explanation", count: 0
    assert_select "input[type=submit]"
    assert_select "a", text: /Bỏ sân này/, count: 0, message: "a single court has nothing to drop"
    assert_equal [ courts(:court_one) ], Booking.pending.map(&:court)
  end

  test "bookings are up to 4 hours" do
    post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "2026-10-20 06:00", 270) } } }
    assert_select "#error_explanation li", text: "Thời lượng phải từ 60 đến 240 phút"

    assert_difference "Booking.count", 1 do
      post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "2026-10-20 06:00", 240) } } }
    end
  end

  test "the third cancellation in a day locks online booking for 7 days" do
    first, second = book(:court_one, "2026-10-20 18:00"), book(:court_one, "2026-10-21 18:00")
    patch cancel_booking_path(first)
    patch cancel_booking_path(second)
    third = book(:court_one, "2026-10-22 18:00")

    get booking_path(third)
    assert_select "[role=note]", text: /lần huỷ thứ 3 trong hôm nay/

    patch cancel_booking_path(third)
    assert_equal Time.zone.parse("2026-10-26 10:00"), users(:an).reload.booking_locked_until

    get root_path
    assert_select "[role=alert]", text: /không thể đặt sân online đến 10:00 ngày 26\/10\/2026/
    assert_no_difference "Booking.count" do
      post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "2026-10-23 18:00", 60) } } }
    end
    assert_select "#error_explanation li", text: /không thể đặt sân online đến 10:00 ngày 26\/10\/2026/

    travel_to Time.zone.parse("2026-10-26 10:01")
    sign_out :user # a week later the session has timed out
    sign_in users(:an)
    assert_difference("Booking.count", 1) { post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "2026-10-27 18:00", 60) } } } }
  end

  test "cancellations on different days or by the owner do not lock" do
    book(:court_one, "2026-10-20 18:00").cancel!(by: users(:an))
    book(:court_one, "2026-10-21 18:00").cancel!(by: users(:owner))
    travel_to(Time.zone.parse("2026-10-19 23:59")) { book(:court_one, "2026-10-22 18:00").cancel!(by: users(:an)) }
    travel_to(Time.zone.parse("2026-10-20 00:01")) { book(:court_one, "2026-10-23 18:00").cancel!(by: users(:an)) }

    assert_nil users(:an).reload.booking_locked_until
  end

  test "the owner can unlock a customer early and still book for them" do
    users(:an).update!(booking_locked_until: 7.days.from_now)
    booking = courts(:court_one).bookings.create!(source: :phone, user: users(:an), customer_name: "Nguyễn An",
                                                  customer_phone: "0901 234 567", starts_at: at("2026-10-20 18:00"), ends_at: at("2026-10-20 19:00"))
    sign_in users(:owner)

    get admin_booking_path(booking)
    assert_select "p", text: /đang bị khoá đặt online/
    patch unlock_booking_admin_user_path(users(:an))

    assert_nil users(:an).reload.booking_locked_until
  end

  private

  def at(time)
    Time.zone.parse(time)
  end

  def book(court, from)
    courts(court).bookings.create!(user: users(:an), starts_at: at(from), ends_at: at(from) + 1.hour)
  end

  def slot(court, from, minutes)
    { court_id: courts(court).id, starts_at: at(from).iso8601, ends_at: (at(from) + minutes.minutes).iso8601 }
  end
end
