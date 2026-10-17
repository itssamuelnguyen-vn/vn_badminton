require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email and phone" do
    user = User.create!(email: "  Binh@Example.COM ", full_name: " Trần  Bình ", phone: "0912 345 678")

    assert_equal "binh@example.com", user.email
    assert_equal "Trần Bình", user.full_name
    assert_equal "+84912345678", user.phone
  end

  test "cannot be destroyed while referenced as the creator of a booking" do
    travel_to Time.zone.parse("2026-10-19 10:00")
    staff = User.create!(email: "staff@example.com", full_name: "Nhân viên")
    courts(:court_one).bookings.create!(kind: :block, created_by: staff,
                                        starts_at: Time.zone.parse("2026-10-20 06:00"), ends_at: Time.zone.parse("2026-10-20 07:00"))

    assert_not staff.destroy
    assert User.exists?(staff.id)
  end
end
