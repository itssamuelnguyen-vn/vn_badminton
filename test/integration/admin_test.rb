require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00") # Monday
    sign_in users(:owner)
  end

  test "only managers can open the admin area" do
    sign_out :user
    get admin_root_path
    assert_redirected_to new_user_session_path

    sign_in users(:an)
    get admin_root_path
    assert_redirected_to root_path
    assert_equal "Bạn không có quyền vào trang quản lý.", flash[:alert]
  end

  test "the header links managers to the admin area" do
    get root_path
    assert_select "header a[href='/admin']", text: "Quản lý"

    sign_in users(:an)
    get root_path
    assert_select "header a[href='/admin']", count: 0
  end

  test "the day board shows bookings, blocks and the day's totals" do
    online = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:30"))
    online.mark_paid!
    courts(:court_two).bookings.create!(kind: :block, note: "Sơn sân", starts_at: at("05:00"), ends_at: at("09:00"))
    courts(:court_two).bookings.create!(user: users(:an), starts_at: at("10:00"), ends_at: at("11:00")).cancel!(by: users(:owner))

    get admin_root_path(date: "2026-10-20")

    assert_response :success
    assert_select "a[href='/admin/bookings/#{online.code}'][style^='grid-area: 28 / 2 / 31 / 3']", text: /Nguyễn An/
    assert_select "a[style*='grid-area: 2 / 3 / 10 / 4']", text: /Sơn sân/
    assert_select "a[aria-label='Đặt Sân 1 lúc 18:00']", count: 0
    assert_select "a[aria-label='Đặt Sân 1 lúc 19:30'][href='/admin/bookings/new?court_id=#{courts(:court_one).id}&date=2026-10-20&start_minute=1170']"
    assert_select "dd", text: "180.000đ", count: 2 # expected and collected
    assert_select "details summary", text: "1 lượt đã huỷ"
  end

  test "the day board names the courts in English" do
    get admin_root_path(date: "2026-10-20", locale: :en)

    assert_select "div.sticky.top-0", text: "Court 1"
    assert_select "a[aria-label='Book Court 2 at 18:00']"
  end

  test "the day board widens its rows to bookings outside the opening hours" do
    courts(:court_one).bookings.create!(kind: :block, starts_at: at("22:00"), ends_at: at("23:00"))

    get admin_root_path(date: "2026-10-20")

    assert_select "div.sticky.left-0", text: "22:30"
  end

  test "books a court for a phone customer and links the booking to their account" do
    assert_difference "Booking.count", 1 do
      post admin_bookings_path, params: { booking: {
        kind: "reservation", court_id: courts(:court_one).id, date: "2026-10-20", start_minute: 1080, end_minute: 1170,
        source: "phone", customer_name: "Anh Bình", customer_phone: "0901 234 567", note: "Khách quen"
      } }
    end

    booking = Booking.last
    assert_redirected_to admin_root_path(date: "2026-10-20")
    assert booking.source_phone?
    assert_equal users(:an), booking.user
    assert_equal users(:owner), booking.created_by
    assert_equal "Anh Bình", booking.customer_name
    assert_equal 180_000, booking.total_amount_vnd
  end

  test "staff bookings skip the online policy but not the opening hours" do
    post admin_bookings_path, params: { booking: {
      kind: "reservation", court_id: courts(:court_one).id, date: "2026-12-01", start_minute: 300, end_minute: 600,
      source: "walk_in", customer_name: "Khách lẻ", customer_phone: "0912 345 678"
    } }
    assert_redirected_to admin_root_path(date: "2026-12-01")
    assert Booking.last.source_walk_in?
    assert_nil Booking.last.user

    assert_no_difference "Booking.count" do
      post admin_bookings_path, params: { booking: {
        kind: "reservation", court_id: courts(:court_one).id, date: "2026-10-20", start_minute: 1290, end_minute: 1350,
        customer_name: "Khách lẻ", customer_phone: "0912 345 678"
      } }
    end
    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Ngoài giờ mở cửa của cơ sở"
  end

  test "blocks a court and removes the block" do
    post admin_bookings_path, params: { booking: {
      kind: "block", court_id: courts(:court_two).id, date: "2026-10-20", start_minute: 300, end_minute: 540,
      customer_name: "ignored", customer_phone: "0901 234 567", note: "Bảo trì"
    } }

    block = Booking.last
    assert block.kind_block?
    assert_nil block.customer_name
    assert_equal "Bảo trì", block.note

    patch cancel_admin_booking_path(block)
    assert block.reload.cancelled?
    assert_equal users(:owner), block.cancelled_by
  end

  test "the booking form is prefilled from an empty cell of the board" do
    get new_admin_booking_path(court_id: courts(:court_two).id, date: "2026-10-20", start_minute: 1080)

    assert_response :success
    assert_select "select[name='booking[court_id]'] option[selected][value='#{courts(:court_two).id}']"
    assert_select "select[name='booking[start_minute]'] option[selected]", text: "18:00"
    assert_select "select[name='booking[end_minute]'] option[selected]", text: "19:00"
  end

  test "checks in, records payment and marks no-shows" do
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))
    other = courts(:court_two).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    get admin_booking_path(booking)
    assert_select "a[href='tel:+84901234567']", text: "0901 234 567"

    patch check_in_admin_booking_path(booking)
    patch mark_paid_admin_booking_path(booking)
    booking.reload
    assert booking.checked_in?
    assert booking.payment_paid?

    patch check_in_admin_booking_path(booking)
    assert_equal "Không thể thực hiện thao tác này với lượt đặt hiện tại.", flash[:alert]

    patch no_show_admin_booking_path(other)
    assert other.reload.no_show?
  end

  test "managers can cancel a booking after the customer cutoff" do
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00", "2026-10-19"), ends_at: at("19:00", "2026-10-19"))
    travel_to Time.zone.parse("2026-10-19 17:30")

    patch cancel_admin_booking_path(booking)

    assert booking.reload.cancelled?
  end

  test "manages price rules" do
    get admin_price_rules_path
    assert_select "td", text: "Cao điểm"

    assert_difference "PriceRule.count", 1 do
      post admin_price_rules_path, params: { price_rule: {
        name: "Sân 2 cuối tuần", court_id: courts(:court_two).id, days_of_week: [ "", "6", "0" ],
        start_minute: 300, end_minute: 1320, price_per_hour_vnd: 150_000, priority: 0, active: "1"
      } }
    end
    rule = PriceRule.last
    assert_equal [ 6, 0 ], rule.days_of_week
    assert_equal courts(:court_two), rule.court

    patch admin_price_rule_path(rule), params: { price_rule: { days_of_week: [ "" ], price_per_hour_vnd: 1500 } }
    assert_response :unprocessable_content
    assert_select "#error_explanation li", count: 2

    patch admin_price_rule_path(rule), params: { price_rule: { active: "0" } }
    assert_not rule.reload.active

    assert_difference "PriceRule.count", -1 do
      delete admin_price_rule_path(rule)
    end
  end

  test "updates the venue settings and opening hours" do
    venue = venues(:phu_nhuan)
    hours = (0..6).to_h { |day| [ day.to_s, { open: "1", opens_minute: "300", closes_minute: "1320" } ] }
    hours["0"] = { open: "0", opens_minute: "300", closes_minute: "1320" }
    hours["6"] = { open: "1", opens_minute: "360", closes_minute: "1440" }

    patch admin_settings_path, params: { settings: { name: venue.name, address: "34 Phan Xích Long", phone: "0283 123 456",
                                                     min_booking_minutes: 60, max_booking_minutes: 240,
                                                     cancellation_cutoff_hours: 4, booking_horizon_days: 30, opening_hours: hours } }

    assert_redirected_to edit_admin_settings_path
    venue.reload
    assert_equal "34 Phan Xích Long", venue.address
    assert_equal 240, venue.max_booking_minutes
    assert_equal 30, venue.booking_horizon_days
    assert_nil venue.opening_hour_for(Date.new(2026, 10, 25)) # Sunday
    assert_equal [ 360, 1440 ], venue.opening_hour_for(Date.new(2026, 10, 24)).then { |oh| [ oh.opens_minute, oh.closes_minute ] }
    assert_equal 6, venue.opening_hours.count
  end

  test "invalid settings change nothing" do
    hours = (0..6).to_h { |day| [ day.to_s, { open: "0" } ] }
    hours["1"] = { open: "1", opens_minute: "1200", closes_minute: "600" }

    patch admin_settings_path, params: { settings: { name: "", address: "x", min_booking_minutes: 60, max_booking_minutes: 180,
                                                     cancellation_cutoff_hours: 2, booking_horizon_days: 14, opening_hours: hours } }

    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: /Thứ hai: Giờ đóng cửa phải sau giờ mở cửa/
    assert_equal 7, venues(:phu_nhuan).opening_hours.count
    assert_equal "Sân Cầu Lông Phú Nhuận", venues(:phu_nhuan).reload.name
  end

  private

  def at(time, date = "2026-10-20")
    Time.zone.parse("#{date} #{time}")
  end
end
