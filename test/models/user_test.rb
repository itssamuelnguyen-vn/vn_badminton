require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email, name and phone" do
    user = create_user(email: "  Binh@Example.COM ", full_name: " Trần  Bình ", phone: "0912 345 678")

    assert_equal "binh@example.com", user.email
    assert_equal "Trần Bình", user.full_name
    assert_equal "+84912345678", user.phone
  end

  test "customers need a phone number, admins do not" do
    customer = User.new(email: "c@example.com", full_name: "C", password: "password123")
    assert_not customer.valid?
    assert customer.errors.added?(:phone, :blank)

    admin = User.new(email: "a@example.com", full_name: "A", password: "password123", role: :admin)
    assert admin.valid?, admin.errors.full_messages.to_sentence
  end

  test "requires a password of at least 8 characters and a valid email" do
    user = User.new(email: "khong-hop-le@example", full_name: "X", phone: "0912345678", password: "short")

    assert_not user.valid?
    assert user.errors.added?(:password, :too_short, count: 8)
    assert user.errors.added?(:email, :invalid, value: "khong-hop-le@example")
  end

  test "email and phone must be unique" do
    user = User.new(email: "AN@example.com", full_name: "X", phone: "0901 234 567", password: "password123")

    assert_not user.valid?
    assert user.errors.added?(:email, :taken, value: "an@example.com")
    assert user.errors.added?(:phone, :taken, value: "+84901234567")
  end

  test "finds a user for sign-in by email or by phone in any common format" do
    an = users(:an)

    [ "an@example.com", " AN@Example.com ", "0901234567", "0901 234 567", "84901234567", "+84 90-123-4567" ].each do |login|
      assert_equal an, User.find_for_database_authentication(login: login), "login: #{login.inspect}"
    end
    [ "", "nobody@example.com", "0999999999", "abc" ].each do |login|
      assert_nil User.find_for_database_authentication(login: login), "login: #{login.inspect}"
    end
  end

  test "cannot be destroyed while referenced as the creator of a booking" do
    travel_to Time.zone.parse("2026-10-19 10:00")
    staff = create_user(email: "staff@example.com", full_name: "Nhân viên", role: :admin)
    courts(:court_one).bookings.create!(kind: :block, created_by: staff,
                                        starts_at: Time.zone.parse("2026-10-20 06:00"), ends_at: Time.zone.parse("2026-10-20 07:00"))

    assert_not staff.destroy
    assert User.exists?(staff.id)
  end

  private

  def create_user(**attrs)
    User.create!(phone: "0912345678", password: "password123", **attrs)
  end
end
