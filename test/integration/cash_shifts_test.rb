require "test_helper"

# "Ca làm": staff and the owner open and close the cash drawer; the owner sees the history (see CashShift).
class CashShiftsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
  end

  test "staff open a shift, take cash at the counter, undo a mistake and close with a short drawer" do
    sign_in users(:staffer)
    get admin_cash_shifts_path
    assert_response :success
    assert_select "a[aria-current=page]", text: "Ca làm"
    assert_select "h2", text: "Chưa mở ca"
    assert_select "h2", text: "Lịch sử chốt ca", count: 0

    post admin_cash_shifts_path, params: { opening_vnd: "500.000" }
    assert_redirected_to admin_cash_shifts_path
    shift = CashShift.sole
    assert_equal [ 500_000, users(:staffer) ], [ shift.opening_vnd, shift.opened_by ]

    paid, mistake = book("2026-10-19 18:00"), book("2026-10-19 19:00")
    patch mark_paid_admin_booking_path(paid)
    patch mark_paid_admin_booking_path(mistake)
    patch undo_payment_admin_booking_path(mistake)

    get admin_cash_shifts_path # blind count: staff see the opening only
    assert_select "dd", text: "500.000đ"
    assert_select "dd", text: "620.000đ", count: 0
    assert_select "li", text: /Khách lẻ · Sân 1 18:00 – 19:00/, count: 0
    assert_select "p", text: /Số tiền dự kiến chỉ chủ sân xem được/

    sign_in users(:owner)
    get admin_cash_shifts_path
    assert_select "dd", text: "120.000đ" # collected
    assert_select "dd", text: "620.000đ" # expected
    assert_select "li", text: /Khách lẻ · Sân 1 18:00 – 19:00/
    assert_select "li", text: /huỷ “đã thu”/
    sign_in users(:staffer)

    patch close_admin_cash_shift_path(shift), params: { counted_vnd: "600000", note: "" }
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /cần ghi lý do/
    assert_not shift.reload.closed?

    patch close_admin_cash_shift_path(shift), params: { counted_vnd: "600000", note: "Thối nhầm cho khách" }
    assert_redirected_to admin_cash_shifts_path
    follow_redirect!
    assert_select "[role=status]", text: /−20.000đ \(thiếu\)/
    shift.reload
    assert_equal [ 120_000, 620_000, 600_000, -20_000, "Thối nhầm cho khách" ], shift.values_at(:collected_vnd, :expected_vnd, :counted_vnd, :difference_vnd, :note)
    assert_select "input[name=opening_vnd][value='600000']", 1, "the next shift starts from the last count"
  end

  test "a refund handed back in cash comes out of the open shift; one by transfer does not" do
    sign_in users(:owner)
    post admin_cash_shifts_path, params: { opening_vnd: "200000" }
    shift = CashShift.sole
    by_cash, by_transfer = book("2026-10-19 18:00"), book("2026-10-19 19:00")
    [ by_cash, by_transfer ].each do |booking|
      patch mark_paid_admin_booking_path(booking)
      patch cancel_venue_fault_admin_booking_path(booking)
    end

    patch mark_refunded_admin_booking_path(by_cash, via: "cash")
    patch mark_refunded_admin_booking_path(by_transfer)
    assert [ by_cash.reload, by_transfer.reload ].all?(&:payment_refunded?)
    assert_equal [ "cash", "transfer" ], [ by_cash, by_transfer ].map { |b| b.events.find_by!(action: "refunded").details["via"] }
    assert_equal 120_000, shift.collected_vnd # 2 x 120.000 paid, 120.000 handed back

    get admin_cash_shifts_path
    assert_select "li", text: /hoàn tiền mặt cho khách/, count: 1
    assert_select "dd", text: "320.000đ" # expected
  end

  test "a second shift cannot be opened while one is open" do
    sign_in users(:staffer)
    post admin_cash_shifts_path, params: { opening_vnd: "0" }
    sign_in users(:owner)
    post admin_cash_shifts_path, params: { opening_vnd: "100000" }

    assert_equal "Đang có một ca chưa chốt. Vui lòng chốt ca đó trước.", flash[:alert]
    assert_equal 1, CashShift.count
  end

  test "the owner sees the history by month and each shift's cash; staff do not" do
    old = CashShift.open!(venue: venues(:phu_nhuan), by: users(:staffer), opening_vnd: 300_000, now: Time.zone.parse("2026-09-30 07:00"))
    old.close!(by: users(:staffer), counted_vnd: 310_000, note: "Khách gửi tiền boa", now: Time.zone.parse("2026-09-30 15:00"))
    october = CashShift.open!(venue: venues(:phu_nhuan), by: users(:staffer), opening_vnd: 0, now: Time.zone.parse("2026-10-19 07:00"))
    october.close!(by: users(:owner), counted_vnd: 0, note: nil, now: Time.zone.parse("2026-10-19 09:00"))

    sign_in users(:owner)
    get admin_cash_shifts_path
    assert_select "section[aria-labelledby=shift-history] ul > li", 1
    assert_select "li", text: /0đ \(khớp\)/
    get admin_cash_shifts_path(month: "2026-09")
    assert_select "li", text: /\+10.000đ \(thừa\)/
    assert_select "li", text: /Khách gửi tiền boa/
    get admin_cash_shift_path(old)
    assert_response :success
    assert_select "p", text: /Chưa thu tiền mặt trong ca này/

    sign_in users(:staffer)
    get admin_cash_shifts_path(month: "2026-09")
    assert_select "li", text: /thừa/, count: 0
    get admin_cash_shift_path(old)
    assert_redirected_to admin_root_path
  end

  test "customers cannot open the cash drawer" do
    sign_in users(:an)
    post admin_cash_shifts_path, params: { opening_vnd: "0" }

    assert_redirected_to root_path
    assert_equal 0, CashShift.count
  end

  private

  def book(from)
    starts_at = Time.zone.parse(from)
    courts(:court_one).bookings.create!(source: :walk_in, customer_name: "Khách lẻ", customer_phone: "0912000111",
                                        starts_at: starts_at, ends_at: starts_at + 1.hour)
  end
end
