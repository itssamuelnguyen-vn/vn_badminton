require "test_helper"

# The app's extra features: moving a booking, extras, announcements, reviews, free court alerts
# and regular booking requests.
class Api::AppExtrasTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers
  include ActionMailer::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @venue = venues(:phu_nhuan)
    @slots = [ { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } ]
  end

  test "moves a booking from the app: the new slot is checked and priced first, a paid one not to a dearer slot" do
    token = sign_in_api(users(:an))
    booking = book_and_pay(token)
    assert ApiJson.booking(booking)[:can_reschedule]

    # The schedule in reschedule mode shows the booking's own slots as available.
    get api_v1_schedule_path(date: "2026-10-20", reschedule: booking.code), headers: auth(token)
    assert_equal "available", state_at(courts(:court_one), "18:00")

    # 08:00-09:30 costs 120 000 instead of 180 000: allowed, the paid amount is kept (no refund of the difference).
    cheaper = { court_id: courts(:court_two).id, starts_at: at("08:00").iso8601, ends_at: at("09:30").iso8601 }
    get reschedule_api_v1_booking_path(booking.code), params: cheaper, headers: auth(token)
    assert_response :success
    assert response.parsed_body["valid"]
    assert_equal 120_000, response.parsed_body.dig("booking", "amount_vnd")
    assert_equal "18:00", booking.reload.starts_at.strftime("%H:%M"), "the review saves nothing"

    patch reschedule_api_v1_booking_path(booking.code), params: cheaper, headers: auth(token), as: :json
    assert_response :success
    assert_equal [ courts(:court_two).id, at("08:00"), 180_000 ], booking.reload.values_at(:court_id, :starts_at, :total_amount_vnd)
    assert_enqueued_email_with BookingMailer, :rescheduled, params: ->(params) { params[:booking] == booking }

    # Back to the dearer evening for longer: refused.
    dearer = { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("20:00").iso8601 }
    patch reschedule_api_v1_booking_path(booking.code), params: dearer, headers: auth(token), as: :json
    assert_response :unprocessable_content
    assert_match "đắt hơn", response.parsed_body["messages"].join
  end

  test "extras picked with a booking are added to the transfer and listed for the staff" do
    racket = @venue.products.create!(name: "Thuê vợt", name_en: "Racket rental", price_vnd: 30_000)
    shuttles = @venue.products.create!(name: "Ống cầu", price_vnd: 250_000)
    old = @venue.products.create!(name: "Nước cũ", price_vnd: 10_000, active: false)
    token = sign_in_api(users(:an))

    get api_v1_venue_path, headers: { "Accept-Language" => "en" }
    assert_equal [ "Racket rental", "Ống cầu" ], response.parsed_body["products"].pluck("name")

    post api_v1_bookings_path, params: { slots: @slots, items: [ { product_id: old.id, quantity: 1 } ] }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    assert_match "không còn bán", response.parsed_body["messages"].join

    items = [ { product_id: racket.id, quantity: 2 }, { product_id: shuttles.id, quantity: 1 } ]
    post api_v1_bookings_path, params: { slots: @slots, items: items }, headers: auth(token), as: :json
    assert_response :created
    assert_equal 180_000 + 60_000 + 250_000, response.parsed_body["amount_vnd"]
    booking = response.parsed_body["bookings"].sole
    assert_equal [ 180_000, 310_000, 490_000 ], booking.values_at("amount_vnd", "items_amount_vnd", "total_vnd")
    assert_equal [ [ "Thuê vợt", 2 ], [ "Ống cầu", 1 ] ], booking["items"].map { |item| item.values_at("name", "quantity") }

    transfer
    assert Booking.find_by!(code: booking["code"]).payment_paid?

    sign_in users(:staffer)
    get admin_root_path(date: "2026-10-20")
    assert_select "p", text: "Chuẩn bị: Thuê vợt × 2, Ống cầu × 1"
  end

  test "the owner posts announcements shown on the booking page and in the app between their dates" do
    sign_in users(:owner)
    post admin_announcements_path, params: { announcement: { title: "Nghỉ lễ 20/11", title_en: "Closed on 20/11", body: "Sân nghỉ cả ngày.",
                                                             starts_on: "2026-10-19", ends_on: "2026-11-20", tone: "warning" } }
    assert_redirected_to admin_announcements_path
    @venue.announcements.create!(title: "Sắp tới", starts_on: "2026-11-01", ends_on: "2026-11-02")

    get api_v1_announcements_path, headers: { "Accept-Language" => "en" }
    assert_equal [ [ "Closed on 20/11", "Sân nghỉ cả ngày.", "warning" ] ], response.parsed_body["announcements"].map { |a| a.values_at("title", "body", "tone") }

    sign_out :user
    get root_path
    assert_select "[role=note]", text: /Nghỉ lễ 20\/11/

    sign_in users(:staffer)
    get admin_announcements_path
    assert_redirected_to admin_root_path
  end

  test "a played session can be reviewed once, within 14 days; the owner and staff read the reviews" do
    token = sign_in_api(users(:an))
    booking = book_and_pay(token)
    post review_api_v1_booking_path(booking.code), params: { rating: 5 }, headers: auth(token), as: :json
    assert_response :unprocessable_content, "not played yet"

    booking.check_in!(now: at("18:05"))
    travel_to at("20:00")
    get api_v1_booking_path(booking.code), headers: auth(token)
    assert response.parsed_body["can_review"]

    post review_api_v1_booking_path(booking.code), params: { rating: 4, comment: "Sân tốt, hơi nóng" }, headers: auth(token), as: :json
    assert_response :created
    assert_equal [ false, 4 ], [ response.parsed_body["can_review"], response.parsed_body.dig("review", "rating") ]
    post review_api_v1_booking_path(booking.code), params: { rating: 1 }, headers: auth(token), as: :json
    assert_response :unprocessable_content, "once per booking"

    sign_in users(:staffer)
    get admin_reviews_path
    assert_response :success
    assert_select "p", text: "Sân tốt, hơi nóng"

    other = book_and_pay(sign_in_api(users(:chi)), slots: [ { court_id: courts(:court_two).id, starts_at: at("21:00").iso8601, ends_at: at("22:00").iso8601 } ])
    other.check_in!(now: at("21:00"))
    travel_to at("22:00") + Review::WINDOW + 1.minute
    post review_api_v1_booking_path(other.code), params: { rating: 3 }, headers: auth(sign_in_api(users(:chi))), as: :json
    assert_response :unprocessable_content, "too late"
  end

  test "customers waiting for a taken time are emailed when a court frees up for all of it" do
    book_and_pay(sign_in_api(users(:chi)))
    taken = book_and_pay(sign_in_api(users(:chi)), slots: [ { court_id: courts(:court_two).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } ])
    token = sign_in_api(users(:an))

    post api_v1_waitlist_entries_path, params: { starts_at: at("18:00").iso8601, ends_at: at("19:00").iso8601 }, headers: auth(token), as: :json
    assert_response :created
    get api_v1_waitlist_entries_path, headers: auth(token)
    assert_equal 1, response.parsed_body["entries"].size

    perform_enqueued_jobs do
      taken.cancel!(by: users(:chi))
    end
    assert_emails 1
    assert_equal "Có sân trống lúc 18:00 ngày 20/10/2026", ActionMailer::Base.deliveries.last.subject
    assert users(:an).waitlist_entries.sole.notified_at
    get api_v1_waitlist_entries_path, headers: auth(token)
    assert_empty response.parsed_body["entries"], "told once"

    WaitlistEntry::MAX_PER_USER.times do |i|
      users(:an).waitlist_entries.create!(starts_at: at("08:00") + i.days, ends_at: at("09:00") + i.days)
    end
    post api_v1_waitlist_entries_path, params: { starts_at: at("10:00").iso8601, ends_at: at("11:00").iso8601 }, headers: auth(token), as: :json
    assert_response :unprocessable_content
  end

  test "a customer asks for a regular booking; the staff create it from the request, and the customer pays the month in the app" do
    token = sign_in_api(users(:an))
    request = { court_ids: [ courts(:court_one).id ], days_of_week: [ 2 ], start_minute: 1080, end_minute: 1200,
                starts_on: "2026-11-03", ends_on: "2026-11-24", note: "Nhóm công ty" }
    post api_v1_series_requests_path, params: request, headers: auth(token), as: :json
    assert_response :created
    series_request = SeriesRequest.find(response.parsed_body["id"])

    sign_in users(:staffer)
    get admin_series_index_path
    assert_select "h2", text: "Yêu cầu từ khách (1)"
    get new_admin_series_path(request_id: series_request.id)
    assert_select "input[name='booking_series[customer_name]'][value='Nguyễn An']"
    post admin_series_index_path, params: { request_id: series_request.id, booking_series: series_request.series_attributes.merge(customer_phone: "0901234567") }
    series = BookingSeries.last
    assert_redirected_to admin_series_path(series)
    assert_equal [ "approved", series ], series_request.reload.values_at(:status, :series)
    assert_enqueued_email_with NoticeMailer, :series_request_decided, params: { series_request: series_request }

    get api_v1_series_index_path, headers: auth(token)
    month = response.parsed_body["series"].sole["months"].sole
    assert_equal [ "2026-11", 4, 4 * 240_000, false ], month.values_at("month", "sessions", "due_vnd", "paid")

    post pay_api_v1_series_path(series), params: { month: "2026-11" }, headers: auth(token), as: :json
    assert_response :success
    assert_equal 960_000, response.parsed_body["amount_vnd"]
    transfer(Payment.find_by!(token: response.parsed_body["token"]))
    get api_v1_series_index_path, headers: auth(token)
    assert response.parsed_body["series"].sole["months"].sole["paid"]
  end

  test "the staff decline a request with a reason; the customer can withdraw a pending one" do
    token = sign_in_api(users(:an))
    request = { court_ids: [ courts(:court_one).id ], days_of_week: [ 6 ], start_minute: 1080, end_minute: 1200, starts_on: "2026-11-07", ends_on: "2026-12-26" }
    2.times { post api_v1_series_requests_path, params: request, headers: auth(token), as: :json }
    declined, withdrawn = users(:an).series_requests.order(:id).to_a

    sign_in users(:staffer)
    patch decline_admin_series_request_path(declined), params: { decline_reason: "Thứ Bảy kín lịch" }
    assert_equal [ "declined", "Thứ Bảy kín lịch" ], declined.reload.values_at(:status, :decline_reason)

    delete api_v1_series_request_path(withdrawn), headers: auth(token)
    assert_equal "cancelled", withdrawn.reload.status
    get api_v1_series_requests_path, headers: auth(token)
    assert_equal %w[cancelled declined], response.parsed_body["requests"].pluck("status").sort

    post api_v1_series_requests_path, params: request.merge(starts_on: "2026-10-19"), headers: auth(token), as: :json
    assert_response :unprocessable_content, "must start tomorrow or later"
  end

  private

  def book_and_pay(token, slots: @slots)
    post api_v1_bookings_path, params: { slots: slots }, headers: auth(token), as: :json
    assert_response :created
    payment = response.parsed_body
    transfer(Payment.find_by!(token: payment["token"]))
    Booking.find_by!(code: payment["bookings"].sole["code"])
  end

  def state_at(court, time)
    response.parsed_body.dig("slots", court.id.to_s).find { |slot| slot["starts_at"] == at(time).iso8601 }["state"]
  end

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
