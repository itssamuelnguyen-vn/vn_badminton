require "test_helper"

class StaffTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.parse("2026-10-19 10:00") }

  test "staff run the day without seeing money, prices, settings or staff" do
    sign_in users(:staffer)
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-19 18:00"), ends_at: Time.zone.parse("2026-10-19 19:00"))

    get admin_root_path
    assert_response :success
    assert_select "nav[aria-label='Quản lý'] a", text: "Lịch trong ngày"
    assert_select "nav[aria-label='Quản lý'] a", text: "Bảng giá", count: 0
    assert_select "nav[aria-label='Quản lý'] a", text: "Vận hành", count: 0 # one group, so no group row
    assert_select "dt", text: "Doanh thu dự kiến", count: 0

    patch check_in_admin_booking_path(booking)
    assert booking.reload.checked_in?

    [ admin_price_rules_path, edit_admin_settings_path, admin_staff_members_path ].each do |path|
      get path
      assert_redirected_to admin_root_path
      assert_equal "Chỉ chủ sân mới vào được trang này.", flash[:alert]
    end
  end

  test "staff can cancel after the customer cutoff, like the owner" do
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-19 11:00"), ends_at: Time.zone.parse("2026-10-19 12:00"))
    sign_in users(:staffer)

    patch cancel_admin_booking_path(booking)
    assert booking.reload.cancelled?
  end

  test "the owner gives and removes staff access" do
    sign_in users(:owner)
    get admin_root_path
    assert_select "dt", text: "Doanh thu dự kiến"

    post admin_staff_members_path, params: { login: "0901 234 567" }
    assert users(:an).reload.staff?
    assert_equal "Nguyễn An giờ là nhân viên.", flash[:notice]

    post admin_staff_members_path, params: { login: "an@example.com" }
    assert_equal "Nguyễn An đã là nhân viên hoặc chủ sân.", flash[:alert]
    post admin_staff_members_path, params: { login: "nobody@example.com" }
    assert_equal "Không tìm thấy tài khoản nào với email hoặc số điện thoại này.", flash[:alert]

    get admin_staff_members_path
    assert_select "div", text: /Nguyễn An/
    delete admin_staff_member_path(users(:an))
    assert users(:an).reload.customer?
  end

  test "the owner cannot be removed from the staff page" do
    sign_in users(:owner)
    delete admin_staff_member_path(users(:owner))
    assert_response :not_found
    assert users(:owner).reload.admin?
  end
end
