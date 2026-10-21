require "test_helper"

# The app's customer features on the web pages: extras and prepaid hours on the confirmation page, the packages
# page, rating a session, waiting for a free court and the member tier.
class WebAppFeaturesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00") # Monday
    @venue = venues(:phu_nhuan)
    # Tuesday 18:00-19:30 on court one: 180 000 (peak).
    @slots = { "0" => { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } }
  end

  test "extras are picked on the confirmation page, priced live and added to the transfer" do
    racket = @venue.products.create!(name: "Thuê vợt", price_vnd: 30_000)
    shuttles = @venue.products.create!(name: "Ống cầu", price_vnd: 250_000)
    old = @venue.products.create!(name: "Nước cũ", price_vnd: 10_000, active: false)
    sign_in users(:an)

    get new_booking_path(slots: @slots)
    assert_select "input[name='booking[quantities][#{racket.id}]'][value='0']"
    assert_select "input[name='booking[quantities][#{old.id}]']", count: 0
    assert_select "#booking_quote dd", text: "180.000đ"

    get quote_bookings_path(booking: { slots: @slots, quantities: { racket.id => "2", shuttles.id => "1" } })
    assert_select "turbo-frame#booking_quote" do
      assert_select "dd", text: "310.000đ" # the extras
      assert_select "dd", text: "490.000đ" # the total
    end
    get quote_bookings_path(booking: { slots: @slots, quantities: { racket.id => "21" } })
    assert_select "#booking_quote li", text: "Số lượng mỗi món từ 1 đến 20."

    post bookings_path, params: { booking: { slots: @slots, quantities: { racket.id => "21" } } }
    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Số lượng mỗi món từ 1 đến 20."
    assert_select "input[name='booking[quantities][#{racket.id}]'][value='21']", 1, "the quantities are kept"

    post bookings_path, params: { booking: { slots: @slots, quantities: { racket.id => "2", shuttles.id => "1", old.id => "0" } } }
    payment = Payment.last
    assert_redirected_to payment_path(payment)
    assert_equal 490_000, payment.amount_vnd
    assert_equal [ [ "Thuê vợt", 2 ], [ "Ống cầu", 1 ] ], payment.bookings.sole.items.map { |item| [ item.name, item.quantity ] }
  end

  test "a voucher code typed on the confirmation page shows its discount or why it cannot be used" do
    @venue.vouchers.create!(code: "HE2026", kind: "amount", value: 20_000, valid_from: "2026-10-01", valid_until: "2026-10-31")
    sign_in users(:an)

    get quote_bookings_path(booking: { slots: @slots, voucher_code: "he2026" })
    assert_select "#booking_quote dt", text: "Ưu đãi Mã HE2026"
    assert_select "#booking_quote dd", text: "160.000đ"

    get quote_bookings_path(booking: { slots: @slots, voucher_code: "nope" })
    assert_select "#booking_quote li", text: "Mã giảm giá không đúng."
  end

  test "prepaid hours are bought on the packages page and pay a booking on the confirmation page" do
    package = @venue.packages.create!(name: "Gói 10 giờ", minutes: 600, price_vnd: 700_000, valid_days: 60)
    @venue.packages.create!(name: "Gói cũ", minutes: 60, price_vnd: 60_000, valid_days: 10, active: false)
    sign_in users(:an)

    get edit_user_registration_path
    assert_select "a[href='#{packages_path}']"
    get packages_path
    assert_response :success
    assert_select "p", text: "Gói 10 giờ"
    assert_select "p", text: "Gói cũ", count: 0

    post buy_package_path(package)
    payment = Payment.last
    assert_redirected_to payment_path(payment)
    assert_equal [ "package", 700_000 ], [ payment.purpose, payment.amount_vnd ]
    get packages_path
    assert_select "span", text: "Chờ chuyển khoản"
    assert_select "a[href='#{payment_path(payment)}']"

    transfer(payment)
    get payment_path(payment)
    assert_select "a[href='#{packages_path}']", text: "Xem gói giờ của tôi"
    purchase = users(:an).package_purchases.sole
    get packages_path
    assert_select "span", text: "Còn 10h / 10h"

    get new_booking_path(slots: @slots)
    assert_select "button[name='booking[package_purchase_id]'][value='#{purchase.id}']"

    racket = @venue.products.create!(name: "Thuê vợt", price_vnd: 30_000)
    post bookings_path, params: { booking: { slots: @slots, package_purchase_id: purchase.id, quantities: { racket.id => "1" } } }
    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Khi trả bằng gói giờ, đồ thuê thêm vui lòng thuê tại quầy."

    assert_enqueued_emails 1 do
      post bookings_path, params: { booking: { slots: @slots, package_purchase_id: purchase.id, quantities: { racket.id => "0" } } }
    end
    booking = users(:an).bookings.confirmed.sole
    assert_redirected_to booking_path(booking)
    assert_equal [ "paid", 0 ], [ booking.payment_status, booking.charged_vnd ]
    assert_equal 510, purchase.reload.minutes_left

    # A package that cannot pay the slots (here: not enough hours left) is not offered.
    purchase.update!(minutes_left: 60)
    get new_booking_path(slots: { "0" => { court_id: courts(:court_two).id, starts_at: at("20:00").iso8601, ends_at: at("21:30").iso8601 } })
    assert_select "button[name='booking[package_purchase_id]']", count: 0
  end

  test "a played session is rated once on its page, then the rating is shown" do
    booking = courts(:court_one).bookings.create!(user: users(:an), source: :online, starts_at: at("18:00"), ends_at: at("19:30"))
    sign_in users(:an)

    get booking_path(booking)
    assert_select "input[name='review[rating]']", { count: 0 }, "not played yet"
    post review_booking_path(booking), params: { review: { rating: 5 } }
    assert_redirected_to booking_path(booking)
    assert_nil booking.reload.review

    booking.check_in!(now: at("18:05"))
    travel_to at("20:00")
    reset! # the earlier session timed out meanwhile
    sign_in users(:an)
    get booking_path(booking)
    assert_select "input[name='review[rating]']", 5

    post review_booking_path(booking), params: { review: { rating: 4, comment: "Sân tốt, hơi nóng" } }
    assert_redirected_to booking_path(booking)
    follow_redirect!
    assert_select "[role=img][aria-label='4 sao']"
    assert_select "p", text: "Sân tốt, hơi nóng"
    assert_select "input[name='review[rating]']", count: 0

    post review_booking_path(booking), params: { review: { rating: 1 } }
    assert_equal 4, booking.reload.review.rating, "once per booking"
  end

  test "a customer waits for a taken time from the schedule and stops waiting from their bookings" do
    courts(:court_one).bookings.create!(user: users(:chi), source: :online, starts_at: at("18:00"), ends_at: at("19:30"))
    get root_path(date: "2026-10-20")
    assert_select "#waitlist", { count: 0 }, "signed in customers only"

    sign_in users(:an)
    get root_path(date: "2026-10-20")
    assert_select "button[data-action='waitlist#pick'][data-court-name='Sân 1'][data-starts-label='18:00']"
    assert_select "#waitlist select[name='waitlist_entry[starts_at]'] option[value='#{at("18:00").iso8601}']"

    post waitlist_entries_path, params: { waitlist_entry: { starts_at: at("18:00").iso8601, ends_at: at("19:00").iso8601 } }
    assert_redirected_to root_path(date: "2026-10-20")
    entry = users(:an).waitlist_entries.sole

    post waitlist_entries_path, params: { waitlist_entry: { starts_at: at("09:00").iso8601, ends_at: at("09:00").iso8601 } }
    assert_match "phải sau giờ bắt đầu", flash[:alert]

    get bookings_path
    assert_select "h2", text: "Đang chờ sân trống"
    assert_select "span", text: "18:00 – 19:00"
    delete waitlist_entry_path(entry)
    assert_redirected_to bookings_path
    assert_empty users(:an).waitlist_entries
    delete waitlist_entry_path(users(:chi).waitlist_entries.create!(starts_at: at("08:00"), ends_at: at("09:00")))
    assert_response :not_found, "only one's own waits"
  end

  test "the account page shows the member tier, the hours played and the next tier" do
    sign_in users(:an)
    get edit_user_registration_path
    assert_select "#loyalty-title + p", text: "Đồng"
    assert_select "p", text: /Chơi thêm 20 giờ để lên hạng Bạc/

    10.times do |i|
      starts_at = (Time.current - (i + 2).days).change(hour: 8)
      Booking.create!(court: courts(:court_two), user: users(:an), source: :walk_in, starts_at: starts_at, ends_at: starts_at + 2.hours,
                      status: :checked_in, checked_in_at: starts_at, payment_status: :paid, paid_at: starts_at)
    end
    get edit_user_registration_path
    assert_select "#loyalty-title + p", text: "Bạc"
    assert_select "span", text: "Giảm 3% tiền sân"
    assert_select "p", text: /Chơi thêm 40 giờ để lên hạng Vàng/

    sign_in users(:staffer)
    get edit_user_registration_path
    assert_select "#loyalty-title", count: 0
  end

  private

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
