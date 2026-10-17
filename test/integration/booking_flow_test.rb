require "test_helper"

class BookingFlowTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.parse("2026-10-19 10:00") } # Monday

  test "the schedule is public and shows a grid for the chosen day" do
    courts(:court_two).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    get root_path(date: "2026-10-20")

    assert_response :success
    assert_select "[role=columnheader]", 2
    assert_select "button[data-available=true][data-court-name='Sân 1'][data-starts-label='18:00']"
    assert_select "div[data-court-name='Sân 2'][data-starts-label='18:00']", text: "Đã đặt"
    assert_select "a[aria-current=date]", text: /20\/10/
  end

  test "after closing time the schedule opens on tomorrow" do
    travel_to Time.zone.parse("2026-10-19 22:30") do
      get root_path
      assert_select "a[aria-current=date]", text: /20\/10/

      get root_path(date: "2026-10-19")
      assert_select "[role=status]", text: /hết giờ có thể đặt/
      assert_select "button[data-available=true]", count: 0
    end
  end

  test "an out-of-range date falls back to today" do
    get root_path(date: "2030-01-01")

    assert_select "a[aria-current=date]", text: /Hôm nay/
  end

  test "picking a slot requires sign-in and comes back to the confirmation page" do
    get new_booking_path(slots: { "0" => slot(:court_one, "18:00", "19:30") })
    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { login: "an@example.com", password: "password123" } }
    assert_redirected_to %r{/bookings/new\?slots}
  end

  test "books a court and sends a confirmation email" do
    sign_in users(:an)

    get new_booking_path(slots: { "0" => slot(:court_one, "18:00", "19:30") })
    assert_response :success
    assert_select "dd", text: "180.000đ"

    assert_enqueued_emails 1 do
      assert_difference "Booking.count", 1 do
        post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "18:00", "19:30") }, note: "Cần thuê vợt" } }
      end
    end

    booking = Booking.last
    assert_redirected_to booking_path(booking)
    assert booking.confirmed?
    assert booking.payment_unpaid?
    assert_equal 180_000, booking.total_amount_vnd
    assert_equal "Cần thuê vợt", booking.note
    assert_equal "+84901234567", booking.customer_phone
  end

  test "the confirmation page explains why a slot cannot be booked" do
    sign_in users(:an)
    courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    get new_booking_path(slots: { "0" => slot(:court_one, "18:30", "19:30") })

    assert_select "#error_explanation li", "Khung giờ này đã có người đặt"
    assert_select "input[type=submit]", count: 0
  end

  test "a failed booking re-renders the confirmation page" do
    sign_in users(:an)

    post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "21:30", "22:30") } } }

    assert_response :unprocessable_content
    assert_select "#error_explanation li", "Ngoài giờ mở cửa của cơ sở"
  end

  test "lists my bookings and lets me cancel before the cutoff" do
    sign_in users(:an)
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))
    other = courts(:court_two).bookings.create!(user: User.create!(email: "x@example.com", full_name: "X", phone: "0912000000", password: "password123"),
                                                starts_at: at("18:00"), ends_at: at("19:00"))

    get bookings_path
    assert_select "a[href='/bookings/#{booking.code}']"
    assert_select "a[href='/bookings/#{other.code}']", count: 0

    patch cancel_booking_path(booking)
    assert_redirected_to bookings_path
    assert booking.reload.cancelled?
    assert_equal users(:an), booking.cancelled_by
  end

  test "cannot see or cancel someone else's booking" do
    sign_in users(:an)
    other = courts(:court_two).bookings.create!(user: User.create!(email: "x@example.com", full_name: "X", phone: "0912000000", password: "password123"),
                                                starts_at: at("18:00"), ends_at: at("19:00"))

    get bookings_path # start the session; the 404 below would not carry the sign-in cookie
    get booking_path(other)
    assert_response :not_found
    patch cancel_booking_path(other)
    assert_response :not_found
    assert other.reload.confirmed?
  end

  test "cancelling after the cutoff is refused" do
    sign_in users(:an)
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    travel_to at("17:00") do
      patch cancel_booking_path(booking)
    end

    assert_redirected_to booking_path(booking)
    assert booking.reload.confirmed?
  end

  test "books several courts at once, each with its own time" do
    sign_in users(:an)
    slots = { "0" => slot(:court_one, "18:00", "19:30"), "1" => slot(:court_two, "19:00", "21:00") }

    get new_booking_path(slots: slots)
    assert_select "span", text: "Tổng tiền (2 sân)"
    assert_select "span", text: "420.000đ"

    assert_enqueued_emails 1 do
      assert_difference "Booking.count", 2 do
        post bookings_path, params: { booking: { slots: slots, note: "Đi nhóm 8 người" } }
      end
    end
    assert_redirected_to bookings_path
    assert_equal [ "Đi nhóm 8 người" ], Booking.last(2).map(&:note).uniq
  end

  test "a customer who booked two courts can cancel just one of them" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "18:00", "19:30"), "1" => slot(:court_two, "18:00", "19:30") } } }
    first, second = Booking.last(2).sort_by { |b| b.court.position }

    patch cancel_booking_path(second)

    assert second.reload.cancelled?
    assert first.reload.confirmed?
  end

  test "books none of the courts when one of them is taken" do
    sign_in users(:an)
    courts(:court_two).bookings.create!(user: users(:an), starts_at: at("19:00"), ends_at: at("20:00"))

    assert_no_difference "Booking.count" do
      post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "18:00", "19:30"), "1" => slot(:court_two, "19:30", "21:00") } } }
    end

    assert_response :unprocessable_content
    assert_select "#error_explanation li", "Sân 2: Khung giờ này đã có người đặt"
  end

  test "the confirmation page without a selection goes back to the schedule" do
    sign_in users(:an)

    get new_booking_path

    assert_redirected_to root_path
  end

  private

  def slot(court, from, to)
    { court_id: courts(court).id, starts_at: at(from).iso8601, ends_at: at(to).iso8601 }
  end

  def at(hhmm)
    Time.zone.parse("2026-10-20 #{hhmm}")
  end
end
