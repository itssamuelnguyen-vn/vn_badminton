require "test_helper"

# Every change to a booking is kept in its history (BookingEvent) with who made it, shown on the admin page.
class BookingHistoryTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
  end

  test "staff actions, undone ones included, are kept with the staff member's name" do
    booking = courts(:court_one).bookings.create!(user: users(:an), source: :walk_in, starts_at: at("18:00"), ends_at: at("19:00"))
    sign_in users(:staffer)

    patch mark_paid_admin_booking_path(booking)
    patch undo_payment_admin_booking_path(booking)
    patch check_in_admin_booking_path(booking)
    patch undo_check_in_admin_booking_path(booking)
    patch no_show_admin_booking_path(booking)
    patch reschedule_admin_booking_path(Booking.create!(court: courts(:court_two), user: users(:chi), starts_at: at("08:00"), ends_at: at("09:00"))),
          params: { booking: { court_id: courts(:court_one).id, date: "2026-10-20", start_minute: 600, end_minute: 660 } }

    assert_equal %w[created paid payment_undone checked_in check_in_undone no_show], booking.events.pluck(:action)
    assert_nil booking.events.first.actor, "made in the test, outside a request"
    assert_equal [ users(:staffer) ], booking.events.where.not(action: "created").map(&:actor).uniq

    get admin_booking_path(booking)
    assert_select "h2", text: "Lịch sử"
    assert_select "li", text: /Đã thu 120.000đ tiền mặt.*Phạm Nhân Viên \(nhân viên\)/m
    assert_select "li", text: /Huỷ “đã thu” 120.000đ/
    assert_select "li", text: /Đánh dấu không đến/

    moved = Booking.find_by!(user: users(:chi))
    assert_equal "rescheduled", moved.events.last.action
    get admin_booking_path(moved)
    assert_select "li", text: %r{Đổi giờ: Sân 2 · 20/10/2026 08:00 – 09:00 → Sân 1 · 20/10/2026 10:00 – 11:00}
  end

  test "an online booking: the customer's hold, the transfer confirming it, the customer's cancellation" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: { "0" => { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } } } }
    booking = Booking.last
    transfer
    patch cancel_booking_path(booking)

    assert_equal %w[created paid cancelled], booking.events.pluck(:action)
    assert_equal [ users(:an), nil, users(:an) ], booking.events.map(&:actor)
    assert_equal "transfer", booking.events.second.details["via"]

    sign_in users(:owner)
    get admin_booking_path(booking)
    assert_select "li", text: /Giữ chỗ chờ chuyển khoản \(Đặt online\): Sân 1 · 20\/10\/2026 18:00 – 19:30 · 180.000đ.*Khách Nguyễn An/m
    assert_select "li", text: /Đã nhận 180.000đ chuyển khoản, lượt đặt được xác nhận.*Hệ thống/m
    assert_select "li", text: /Huỷ lượt đặt.*Khách Nguyễn An/m
  end

  private

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
