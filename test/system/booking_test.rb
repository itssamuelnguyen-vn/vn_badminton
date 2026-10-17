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
    click_on "Xác nhận đặt sân"

    assert_text "Đặt sân thành công!"
    booking = Booking.last
    assert_equal [ courts(:court_one), Time.zone.parse("2026-10-20 18:00"), Time.zone.parse("2026-10-20 19:30") ],
                 [ booking.court, booking.starts_at, booking.ends_at ]
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

  private

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
