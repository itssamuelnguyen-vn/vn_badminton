require "test_helper"

class CustomersTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    sign_in users(:owner)
  end

  test "lists customers with an account and customers booked by phone, searchable" do
    book(users(:an), "18:00")
    courts(:court_two).bookings.create!(source: :phone, customer_name: "Anh Bình", customer_phone: "0912 000 111",
                                        starts_at: at("18:00"), ends_at: at("19:00")).update!(status: :no_show)

    get admin_customers_path
    assert_select "a[href='/admin/customers/0901234567']", text: /Nguyễn An/
    assert_select "a[href='/admin/customers/0912000111']", text: /Anh Bình.*1 lần không đến/m
    assert_select "a[href='/admin/customers/0933000111']", text: /Lê Chi/ # an account without bookings

    get admin_customers_path(q: "0912 000")
    assert_select "a[href^='/admin/customers/']", 1
    get admin_customers_path(q: "chi")
    assert_select "a[href='/admin/customers/0933000111']"
    assert_select "a[href='/admin/customers/0901234567']", count: 0
  end

  test "the customer page shows the history, keeps a note and blacklists" do
    booking = book(users(:an), "18:00")

    get admin_customer_path("0901234567")
    assert_select "h1", "Nguyễn An"
    assert_select "a[href='/admin/bookings/#{booking.code}']"
    assert_select "dt", text: "Doanh thu"

    patch admin_customer_path("0901234567"), params: { customer_profile: { note: "Khách quen", blocked: "1", blocked_reason: "Hay bỏ sân" } }
    profile = CustomerProfile.find_by!(phone: "+84901234567")
    assert_equal "Khách quen", profile.note
    assert profile.blocked?
    assert_equal users(:owner), profile.blocked_by

    get admin_booking_path(booking)
    assert_select "[role=status]", text: /danh sách đen.*Hay bỏ sân/

    patch admin_customer_path("0901234567"), params: { customer_profile: { note: "Khách quen", blocked: "0" } }
    assert_not profile.reload.blocked?
  end

  test "blacklisted customers cannot book online, but the venue can book for them" do
    CustomerProfile.create!(phone: "0901 234 567").tap { |p| p.block(by: users(:owner), reason: "x") }.save!
    sign_in users(:an)

    assert_no_difference("Booking.count") { post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "18:00", "19:00") } } } }
    assert_select "#error_explanation li", text: /không thể đặt sân online/

    sign_in users(:owner)
    assert_difference("Booking.count", 1) do
      post admin_bookings_path, params: { booking: { kind: "reservation", court_id: courts(:court_one).id, date: "2026-10-20",
                                                     start_minute: 1080, end_minute: 1140, customer_name: "Nguyễn An", customer_phone: "0901234567" } }
    end
  end

  test "staff see customers but not their revenue" do
    book(users(:an), "18:00")
    sign_in users(:staffer)

    get admin_customer_path("0901234567")
    assert_response :success
    assert_select "dt", text: "Doanh thu", count: 0
  end

  test "an unknown phone number is not found" do
    get admin_customer_path("0999999999")
    assert_response :not_found
  end

  private

  def at(time) = Time.zone.parse("2026-10-20 #{time}")

  def book(user, from)
    courts(:court_one).bookings.create!(user: user, starts_at: at(from), ends_at: at(from) + 1.hour)
  end

  def slot(court, from, to)
    { court_id: courts(court).id, starts_at: at(from).iso8601, ends_at: at(to).iso8601 }
  end
end
