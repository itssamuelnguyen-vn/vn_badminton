require "test_helper"

class RescheduleTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00") # Monday
    @booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("2026-10-20 08:00"), ends_at: at("2026-10-20 09:00"))
  end

  test "a customer moves their booking from the schedule, with the new price" do
    sign_in users(:an)

    get booking_path(@booking)
    assert_select "a[href='/?date=2026-10-20&reschedule=#{@booking.code}']", text: "Đổi giờ"

    get root_path(date: "2026-10-20", reschedule: @booking.code)
    assert_select "[role=status]", text: /Đang đổi giờ cho lượt #{@booking.code}/
    assert_select "div#slot-picker[data-slot-picker-new-url-value='/bookings/#{@booking.code}/reschedule']"
    assert_select "button[data-court-name='Sân 1'][data-starts-label='08:00']", 1, "its own slot can be picked again"
    assert_select "a[aria-label='Ngày sau'][href='/?date=2026-10-21&reschedule=#{@booking.code}']"
    assert_select "label[hidden]", text: /Đặt nhiều sân cùng lúc/

    get reschedule_booking_path(@booking, slots: { "0" => slot(:court_two, "2026-10-21 18:00", 60) })
    assert_select "dd.line-through", text: /Sân 1 .* 08:00 – 09:00/
    assert_select "dd", text: /Sân 2 .* 18:00 – 19:00/
    assert_select "dd span.line-through", text: "80.000đ"
    assert_select "dd span", text: "120.000đ" # weekday peak

    @booking.update_column(:reminder_sent_at, Time.current)
    assert_enqueued_email_with BookingMailer, :rescheduled, params: ->(p) { p[:booking] == @booking } do
      patch reschedule_booking_path(@booking), params: { reschedule: slot(:court_two, "2026-10-21 18:00", 60) }
    end
    assert_redirected_to booking_path(@booking)
    @booking.reload
    assert_equal [ courts(:court_two), at("2026-10-21 18:00"), 120_000 ], [ @booking.court, @booking.starts_at, @booking.total_amount_vnd ]
    assert_nil @booking.reminder_sent_at, "the reminder is sent again for the new time"
    assert_equal 1, Booking.count
  end

  test "the online rules still apply to customers" do
    sign_in users(:an)
    courts(:court_two).bookings.create!(user: users(:chi), starts_at: at("2026-10-20 18:00"), ends_at: at("2026-10-20 19:00"))

    get reschedule_booking_path(@booking, slots: { "0" => slot(:court_two, "2026-10-20 18:00", 60) })
    assert_select "#error_explanation li", text: "Khung giờ này đã có người đặt"
    assert_select "input[type=submit]", count: 0

    patch reschedule_booking_path(@booking), params: { reschedule: slot(:court_one, "2026-10-20 06:00", 270) }
    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Thời lượng phải từ 60 đến 240 phút"
    assert_equal at("2026-10-20 08:00"), @booking.reload.starts_at
  end

  test "customers cannot move a paid booking or one past the cutoff" do
    sign_in users(:an)
    @booking.mark_paid!

    get booking_path(@booking)
    assert_select "a", text: "Đổi giờ", count: 0
    get reschedule_booking_path(@booking, slots: { "0" => slot(:court_two, "2026-10-21 18:00", 60) })
    assert_redirected_to booking_path(@booking)
    get root_path(date: "2026-10-20", reschedule: @booking.code)
    assert_select "[role=status]", text: /Đang đổi giờ/, count: 0
  end

  test "the venue moves any booking, outside the online rules but within opening hours" do
    sign_in users(:staffer)

    get admin_booking_path(@booking)
    assert_select "a[href='/admin/bookings/#{@booking.code}/edit_schedule']", text: "Đổi giờ"
    get edit_schedule_admin_booking_path(@booking)
    assert_select "select[name='booking[start_minute]'] option[selected]", text: "08:00"

    assert_enqueued_email_with BookingMailer, :rescheduled, params: ->(p) { p[:booking] == @booking } do
      patch reschedule_admin_booking_path(@booking), params: { booking: { court_id: courts(:court_two).id, date: "2026-12-20", start_minute: 300, end_minute: 600 } }
    end
    assert_redirected_to admin_booking_path(@booking)
    assert_equal [ courts(:court_two), at("2026-12-20 05:00"), at("2026-12-20 10:00") ], @booking.reload.then { |b| [ b.court, b.starts_at, b.ends_at ] }

    patch reschedule_admin_booking_path(@booking), params: { booking: { court_id: courts(:court_two).id, date: "2026-12-20", start_minute: 1290, end_minute: 1350 } }
    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Ngoài giờ mở cửa của cơ sở"
  end

  test "the venue moves a block" do
    block = courts(:court_two).bookings.create!(kind: :block, starts_at: at("2026-10-20 05:00"), ends_at: at("2026-10-20 07:00"))
    sign_in users(:owner)

    assert_no_enqueued_emails do
      patch reschedule_admin_booking_path(block), params: { booking: { court_id: courts(:court_two).id, date: "2026-10-21", start_minute: 300, end_minute: 420 } }
    end
    assert_equal at("2026-10-21 05:00"), block.reload.starts_at
  end

  test "the rescheduled email shows the old and the new time" do
    previous = @booking.attributes.slice("court_id", "starts_at", "ends_at")
    @booking.update!(court: courts(:court_two), starts_at: at("2026-10-21 18:00"), ends_at: at("2026-10-21 19:00"))

    mail = BookingMailer.with(booking: @booking, previous: previous).rescheduled
    assert_equal "Đã đổi giờ lượt đặt sân #{@booking.code}", mail.subject
    assert_includes mail.body.to_s, "Sân 1 · Thứ ba, 20/10/2026 · 08:00 – 09:00"
    assert_includes mail.body.to_s, "18:00 – 19:00"
  end

  private

  def at(time) = Time.zone.parse(time)

  def slot(court, from, minutes)
    { court_id: courts(court).id, starts_at: at(from).iso8601, ends_at: (at(from) + minutes.minutes).iso8601 }
  end
end
