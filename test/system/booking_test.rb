require "application_system_test_case"

class BookingTest < ApplicationSystemTestCase
  setup { travel_to Time.zone.parse("2026-10-19 10:00") } # Monday

  test "picks consecutive slots on the schedule and books them" do
    sign_in_as users(:an)
    visit root_path(date: "2026-10-20")

    slot("Sân 1", "18:00").click
    assert_text "Vui lòng chọn tối thiểu 60 phút"
    assert_selector "a[aria-disabled=true]", text: "Tiếp tục"

    slot("Sân 1", "19:00").click
    assert_text "Sân 1 · 18:00 – 19:30 · 180.000đ"
    assert_no_text "Vui lòng chọn tối thiểu"

    click_on "Tiếp tục"
    assert_selector "h1", text: "Xác nhận đặt sân"
    fill_in "Ghi chú", with: "Cần thuê vợt"
    click_on "Xác nhận & chuyển khoản"

    assert_selector "h1", text: "Chuyển khoản" # wait for the request before reading the database
    payment = Payment.last
    assert_selector "img[src*='des=#{payment.code}']"
    assert_text "180.000đ"
    booking = Booking.last
    assert_equal [ courts(:court_one), Time.zone.parse("2026-10-20 18:00"), Time.zone.parse("2026-10-20 19:30") ],
                 [ booking.court, booking.starts_at, booking.ends_at ]

    pay(payment)
    assert_selector "h1", text: "Đã nhận được tiền"
    click_on "Xem lượt đặt"
    assert_selector "p", text: booking.code
  end

  test "a selection cannot jump over a booked slot" do
    courts(:court_one).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-20 18:30"),
                                        ends_at: Time.zone.parse("2026-10-20 19:30"))
    visit root_path(date: "2026-10-20")

    slot("Sân 1", "17:00").click
    slot("Sân 1", "20:00").click

    assert_text "Sân 1 · 20:00 – 20:30"
  end

  test "books two courts with the several-courts box ticked" do
    sign_in_as users(:an)
    visit root_path(date: "2026-10-20")

    slot("Sân 1", "18:00").click
    slot("Sân 1", "19:00").click
    slot("Sân 2", "19:00").click
    assert_no_text "Sân 1 · 18:00", wait: 0.5 # without the box, another court replaces the selection

    check "Đặt nhiều sân cùng lúc"
    slot("Sân 2", "20:30").click
    slot("Sân 1", "18:00").click
    slot("Sân 1", "19:00").click
    assert_text "Sân 1 · 18:00 – 19:30 · 180.000đ"
    assert_text "Sân 2 · 19:00 – 21:00 · 240.000đ"
    assert_text "Tổng cộng: 420.000đ"

    click_on "Tiếp tục"
    click_on "Xác nhận & chuyển khoản"

    assert_text "420.000đ" # one transfer for both courts
    pay(Payment.last)
    assert_selector "h1", text: "Đã nhận được tiền"
    assert_equal [ [ "Sân 1", "18:00", "19:30" ], [ "Sân 2", "19:00", "21:00" ] ],
                 Booking.order(:starts_at).map { |b| [ b.court.display_name, b.starts_at.strftime("%H:%M"), b.ends_at.strftime("%H:%M") ] }
  end

  test "unticking the box keeps only the court picked last" do
    visit root_path(date: "2026-10-20")

    check "Đặt nhiều sân cùng lúc"
    slot("Sân 1", "18:00").click
    slot("Sân 2", "19:00").click
    uncheck "Đặt nhiều sân cùng lúc"

    assert_text "Sân 2 · 19:00 – 19:30"
    assert_no_text "Sân 1 · 18:00"
  end

  private

  # The transfer reported by SePay, then the page reloaded (live updates need Action Cable, not used in tests).
  def pay(payment)
    Payments::Webhook.process({ "id" => SecureRandom.random_number(10**9), "content" => "#{payment.code} ck", "transferType" => "in",
                                "transferAmount" => payment.amount_vnd })
    visit current_path
  end

  def slot(court, time)
    find("button[data-court-name='#{court}'][data-starts-label='#{time}']")
  end

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "user_login", with: user.email
    fill_in "user_password", with: "password123"
    find("form input[type=submit]").click
    assert_selector "header", text: user.full_name
  end
end
