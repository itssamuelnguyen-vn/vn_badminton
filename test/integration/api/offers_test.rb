require "test_helper"

# Member tiers, vouchers and prepaid hours: the best single offer is taken off the court price.
class Api::OffersTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @venue = venues(:phu_nhuan)
    # Tuesday 18:00-19:30 on court one: 180 000 (peak).
    @slots = [ { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } ]
  end

  test "hours played in the last 12 months make the tier, and its discount comes off online bookings" do
    token = sign_in_api(users(:an))
    get api_v1_account_path, headers: auth(token)
    assert_equal [ "bronze", 0 ], response.parsed_body["loyalty"].values_at("tier", "percent")

    played(users(:an), hours: 20)
    played(users(:an), hours: 10, ago: 13.months) # too old to count
    get api_v1_account_path, headers: auth(token)
    loyalty = response.parsed_body["loyalty"]
    assert_equal [ "silver", "Bạc", 3, 20.0 ], loyalty.values_at("tier", "name", "percent", "hours")
    assert_equal [ "gold", 60 ], loyalty["next"].values_at("tier", "hours")

    post api_v1_quote_path, params: { slots: @slots }, headers: auth(token), as: :json
    assert_equal [ 180_000, 5_000, 175_000, "tier" ], response.parsed_body.values_at("court_vnd", "discount_vnd", "total_vnd").push(response.parsed_body.dig("offer", "kind"))

    post api_v1_bookings_path, params: { slots: @slots }, headers: auth(token), as: :json
    assert_equal [ 175_000, 5_000, "tier" ], response.parsed_body.values_at("amount_vnd", "discount_vnd", "offer")
    booking = Booking.find_by!(code: response.parsed_body["bookings"].sole["code"])
    assert_equal [ 180_000, 5_000, 175_000 ], [ booking.total_amount_vnd, booking.discount_vnd, booking.charged_vnd ]

    @venue.update!(loyalty_enabled: false)
    post api_v1_quote_path, params: { slots: @slots }, headers: auth(token), as: :json
    assert_equal 0, response.parsed_body["discount_vnd"]
  end

  test "a voucher replaces the tier when it saves more, within its limits" do
    voucher = @venue.vouchers.create!(code: "he2026", kind: "percent", value: 10, max_discount_vnd: 15_000, valid_from: "2026-10-01",
                                      valid_until: "2026-10-31", per_user_limit: 1, usage_limit: 5)
    played(users(:an), hours: 20)
    token = sign_in_api(users(:an))

    post api_v1_quote_path, params: { slots: @slots, voucher_code: "nope" }, headers: auth(token), as: :json
    assert_equal [ "Mã giảm giá không đúng." ], response.parsed_body["messages"]
    post api_v1_bookings_path, params: { slots: @slots, voucher_code: "nope" }, headers: auth(token), as: :json
    assert_response :unprocessable_content, "a wrong code stops the order"

    # 10% of 180 000 is 18 000, capped at 15 000: more than the tier's 5 000.
    post api_v1_bookings_path, params: { slots: @slots, voucher_code: " HE2026 " }, headers: auth(token), as: :json
    assert_response :created
    assert_equal [ 165_000, 15_000, "voucher" ], response.parsed_body.values_at("amount_vnd", "discount_vnd", "offer")
    assert_equal 1, voucher.uses

    other = [ { court_id: courts(:court_two).id, starts_at: at("08:00").iso8601, ends_at: at("09:00").iso8601 } ]
    post api_v1_quote_path, params: { slots: other, voucher_code: "HE2026" }, headers: auth(token), as: :json
    assert_equal [ "Bạn đã dùng hết lượt của mã này." ], response.parsed_body["messages"]

    # An expired transfer gives the use back.
    Payment.last.bookings.each { |booking| booking.update_columns(expires_at: 1.minute.ago) }
    Booking.release_expired_holds!(nil, now: Time.current + Payment::WINDOW + Payment::GRACE + 1.minute)
    assert_equal 0, voucher.uses

    # Amount voucher saving less than the tier: the tier stays, the order goes on.
    @venue.vouchers.create!(code: "NHO", kind: "amount", value: 1_000, valid_from: "2026-10-01", valid_until: "2026-10-31")
    post api_v1_bookings_path, params: { slots: other, voucher_code: "NHO" }, headers: auth(token), as: :json
    assert_response :created
    assert_equal "tier", response.parsed_body["offer"]
  end

  test "a voucher can be limited to days and times" do
    @venue.vouchers.create!(code: "SANGSOM", kind: "amount", value: 20_000, valid_from: "2026-10-01", valid_until: "2026-12-31",
                            days_of_week: [ 1, 2, 3, 4, 5 ], start_minute: 300, end_minute: 960)
    token = sign_in_api(users(:an))
    post api_v1_quote_path, params: { slots: @slots, voucher_code: "SANGSOM" }, headers: auth(token), as: :json
    assert_equal [ "Mã này không dùng cho khung giờ bạn chọn." ], response.parsed_body["messages"]

    morning = [ { court_id: courts(:court_one).id, starts_at: at("07:00").iso8601, ends_at: at("08:00").iso8601 } ]
    post api_v1_quote_path, params: { slots: morning, voucher_code: "SANGSOM" }, headers: auth(token), as: :json
    assert_equal [ 80_000, 20_000, 60_000 ], response.parsed_body.values_at("court_vnd", "discount_vnd", "total_vnd")
  end

  test "a code whose discount rounds down to nothing says so and stops the order" do
    # 10% of 6 000 is 600, under the 1 000đ the discounts are rounded to.
    @venue.vouchers.create!(code: "NHO10", kind: "percent", value: 10, valid_from: "2026-10-01", valid_until: "2026-10-31")
    token = sign_in_api(users(:an))
    post api_v1_quote_path, params: { slots: @slots, voucher_code: "NHO10" }, headers: auth(token), as: :json
    assert_equal 18_000, response.parsed_body["discount_vnd"], "a real price is discounted"

    PriceRule.update_all(price_per_hour_vnd: 4_000) # 1.5 hours: 6 000, like a test price
    post api_v1_quote_path, params: { slots: @slots, voucher_code: "NHO10" }, headers: auth(token), as: :json
    assert_equal [ 6_000, 0, [ "Mã này không giảm được cho đơn này (số tiền giảm dưới 1.000đ)." ] ],
                 response.parsed_body.values_at("total_vnd", "discount_vnd", "messages")
    post api_v1_bookings_path, params: { slots: @slots, voucher_code: "NHO10" }, headers: auth(token), as: :json
    assert_response :unprocessable_content
  end

  test "the web's confirmation page takes a voucher code too" do
    @venue.vouchers.create!(code: "WEB10", kind: "amount", value: 10_000, valid_from: "2026-10-01", valid_until: "2026-10-31")
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: { "0" => @slots.first }, voucher_code: "web10" } }
    assert_redirected_to payment_path(Payment.last)
    assert_equal [ 170_000, 10_000 ], Payment.last.values_at(:amount_vnd, :discount_vnd)
  end

  test "prepaid hours are bought by transfer and pay bookings; the customer's cancellation keeps them, the venue's fault gives them back" do
    package = @venue.packages.create!(name: "Gói 10 giờ", minutes: 600, price_vnd: 700_000, valid_days: 60)
    off_peak = @venue.packages.create!(name: "Gói sáng", minutes: 120, price_vnd: 120_000, valid_days: 30, start_minute: 300, end_minute: 960)
    token = sign_in_api(users(:an))

    get api_v1_packages_path, headers: auth(token)
    assert_equal [ "Gói sáng", "Gói 10 giờ" ], response.parsed_body["packages"].pluck("name")

    post buy_api_v1_package_path(package), headers: auth(token)
    assert_response :created
    assert_equal [ 700_000, "package" ], response.parsed_body.values_at("amount_vnd", "purpose")
    transfer(Payment.find_by!(token: response.parsed_body["token"]))
    purchase = users(:an).package_purchases.sole
    assert purchase.active?
    assert_equal (Time.current + 60.days).end_of_day.to_i, purchase.expires_at.to_i

    post api_v1_quote_path, params: { slots: @slots, package_purchase_id: purchase.id }, headers: auth(token), as: :json
    assert_equal [ 0, "package" ], [ response.parsed_body["total_vnd"], response.parsed_body.dig("offer", "kind") ]

    racket = @venue.products.create!(name: "Thuê vợt", price_vnd: 30_000)
    post api_v1_bookings_path, params: { slots: @slots, package_purchase_id: purchase.id, items: [ { product_id: racket.id, quantity: 1 } ] },
                               headers: auth(token), as: :json
    assert_response :unprocessable_content, "extras are rented at the counter with prepaid hours"

    post api_v1_bookings_path, params: { slots: @slots, package_purchase_id: purchase.id }, headers: auth(token), as: :json
    assert_response :created
    booking = Booking.find_by!(code: response.parsed_body["bookings"].sole["code"])
    assert_equal [ "confirmed", "paid", 0, true ], [ booking.status, booking.payment_status, booking.charged_vnd, response.parsed_body["bookings"].sole["paid_with_package"] ]
    assert_equal 510, purchase.reload.minutes_left

    booking.cancel!(by: users(:an))
    assert_equal 510, purchase.reload.minutes_left, "the customer's cancellation keeps the hours used"

    second = [ { court_id: courts(:court_two).id, starts_at: at("20:00").iso8601, ends_at: at("21:00").iso8601 } ]
    post api_v1_bookings_path, params: { slots: second, package_purchase_id: purchase.id }, headers: auth(token), as: :json
    played_booking = Booking.find_by!(code: response.parsed_body["bookings"].sole["code"])
    played_booking.cancel_for_venue_fault!(by: users(:owner))
    assert_equal 510, purchase.reload.minutes_left, "the venue's fault gives the hours back"
    assert_nil played_booking.reload.refund_vnd, "no money to refund"

    post buy_api_v1_package_path(off_peak), headers: auth(token)
    transfer(Payment.find_by!(token: response.parsed_body["token"]))
    post api_v1_bookings_path, params: { slots: @slots, package_purchase_id: users(:an).package_purchases.last.id }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    assert_match "không dùng cho khung giờ", response.parsed_body["messages"].join

    sign_in users(:owner)
    get admin_reports_path(month: "2026-10")
    assert_select "p", text: /Bán gói giờ trong tháng: 820\.000/
  end

  test "the owner sets up vouchers, packages and the tiers" do
    sign_in users(:owner)
    post admin_vouchers_path, params: { voucher: { code: "le30", kind: "amount", value: 30_000, valid_from: "2026-10-01", valid_until: "2026-10-31",
                                                   per_user_limit: 1, days_of_week: [ "", "6", "0" ] } }
    assert_redirected_to admin_vouchers_path
    assert_equal [ "LE30", [ 0, 6 ] ], Voucher.last.values_at(:code, :days_of_week)

    post admin_packages_path, params: { package: { name: "Gói 5 giờ", hours: "5", price_vnd: 380_000, valid_days: 30 } }
    assert_redirected_to admin_packages_path
    assert_equal 300, Package.last.minutes

    patch admin_settings_path, params: { settings: { silver_hours: 30, gold_hours: 20 } }
    assert_response :unprocessable_content

    sign_in users(:staffer)
    get admin_vouchers_path
    assert_redirected_to admin_root_path
  end

  private

  # Sessions the customer played and paid, two hours each, ending `ago` before now: confirmed and paid is enough,
  # nobody records check-ins.
  def played(user, hours:, ago: 1.day)
    (hours / 2).times do |i|
      starts_at = (Time.current - ago - (i + 1).days).change(hour: 8)
      Booking.create!(court: courts(:court_two), user: user, source: :walk_in, starts_at: starts_at, ends_at: starts_at + 2.hours,
                      payment_status: :paid, paid_at: starts_at)
    end
  end

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
