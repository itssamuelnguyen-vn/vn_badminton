require "test_helper"

# The confirmation page holds the picked slots for Booking::HOLD_DURATION (3 minutes).
class BookingHoldTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @slots = { "0" => slot(:court_one, "18:00", "19:00") }
  end

  test "opening the confirmation page holds the slots for 3 minutes and shows a countdown" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)

    hold = Booking.pending.sole
    assert_equal users(:an), hold.user
    assert_equal 3.minutes.from_now, hold.expires_at
    assert_select "[role=timer][data-hold-countdown-seconds-value='180']", text: /Khung giờ đang được giữ cho bạn/
    assert_select "button[name=_method][value=delete][formaction='/bookings/release_hold?date=2026-10-20']", text: "Chọn giờ khác"

    get bookings_path
    assert_select "a[href='/bookings/#{hold.code}']", count: 0, message: "a hold is not a booking yet"
  end

  test "the owner and staff see who is holding slots, with their phone number; customers do not" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)
    hold = Booking.pending.sole

    sign_in users(:staffer)
    get root_path(date: "2026-10-20")
    assert_select "h2", text: "Khách đang giữ chỗ (1)"
    assert_select "a[href='/admin/bookings/#{hold.code}']", text: "18:00 – 19:00 · Sân 1"
    assert_select "a[href='tel:+84901234567']", text: "0901 234 567"
    assert_select "p", text: "Đang xác nhận · giữ đến 10:03"

    get root_path(date: "2026-10-21")
    assert_select "h2", text: "Khách đang giữ chỗ (0)"

    sign_in users(:chi)
    get root_path(date: "2026-10-20")
    assert_select "h2", text: /Khách đang giữ chỗ/, count: 0
    assert_select "a[href^='tel:']", count: 0
  end

  test "other customers see held slots as taken and cannot hold them" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)

    sign_in users(:chi)
    get root_path(date: "2026-10-20")
    assert_select "div[data-court-name='Sân 1'][data-starts-label='18:00']", text: "Đang giữ"
    assert_select "button[data-court-name='Sân 1'][data-starts-label='18:00']", count: 0

    get new_booking_path(slots: @slots)
    assert_select "#error_explanation li", text: "Khung giờ này đã có người đặt"
    assert_select "[role=timer]", count: 0
  end

  test "the holder still sees the slots as free and reloading does not extend the hold" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)
    expires_at = Booking.pending.sole.expires_at

    get root_path(date: "2026-10-20")
    assert_select "button[data-court-name='Sân 1'][data-starts-label='18:00']"

    travel 1.minute
    get new_booking_path(slots: @slots)
    assert_equal expires_at, Booking.pending.sole.expires_at
    assert_select "[role=timer][data-hold-countdown-seconds-value='120']"
  end

  test "picking other slots replaces the hold, and 'pick another time' releases it" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)
    get new_booking_path(slots: { "0" => slot(:court_two, "19:00", "20:00") })
    assert_equal [ courts(:court_two) ], Booking.pending.map(&:court)

    delete release_hold_bookings_path(date: "2026-10-20")
    assert_redirected_to root_path(date: "2026-10-20")
    assert_empty Booking.pending
  end

  test "after 3 minutes another customer can take the slots" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)

    travel 3.minutes + 1.second
    sign_in users(:chi)
    get root_path(date: "2026-10-20")
    assert_select "button[data-court-name='Sân 1'][data-starts-label='18:00']"

    post bookings_path, params: { booking: { slots: @slots } }
    assert_difference("Booking.confirmed.count", 1) { transfer }
    assert_equal users(:chi), Booking.confirmed.sole.user
    assert_empty Booking.pending, "the expired hold was released"
  end

  test "confirming late still works when nobody took the slots, and fails when someone did" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)
    travel 5.minutes

    post bookings_path, params: { booking: { slots: @slots } }
    transfer
    assert_equal [ "confirmed" ], Booking.where(user: users(:an)).pluck(:status)

    get new_booking_path(slots: { "0" => slot(:court_two, "18:00", "19:00") })
    travel 5.minutes
    assert BookingBatch.new(user: users(:chi), slots: [ { court_id: courts(:court_two).id, starts_at: at("18:00"), ends_at: at("19:00") } ]).reserve
    post bookings_path, params: { booking: { slots: { "0" => slot(:court_two, "18:00", "19:00") } } }
    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Khung giờ này đã có người đặt"
  end

  test "the owner's day board shows a hold as waiting for confirmation" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)

    sign_in users(:owner)
    get admin_root_path(date: "2026-10-20")
    assert_select "a[href='/admin/bookings/#{Booking.pending.sole.code}']", text: /Chờ xác nhận/
  end

  test "Continue on the schedule is not prefetched, since opening the page holds slots" do
    get root_path(date: "2026-10-20")
    assert_select "a[data-slot-picker-target=continue][data-turbo-prefetch=false]"
  end

  private

  def at(time)
    Time.zone.parse("2026-10-20 #{time}")
  end

  def slot(court, from, to)
    { court_id: courts(court).id, starts_at: at(from).iso8601, ends_at: at(to).iso8601 }
  end
end
