require "test_helper"

# Regular customers' weekly bookings, paid per calendar month (see BookingSeries).
class BookingSeriesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00") # Monday
    sign_in users(:owner)
  end

  test "previews every session, skips the taken ones and creates the rest on several courts" do
    courts(:court_two).bookings.create!(user: users(:chi), starts_at: at("2026-10-27 19:00"), ends_at: at("2026-10-27 20:00"))

    post preview_admin_series_index_path, params: series_params
    assert_response :success
    assert_select "dd", text: "7" # 4 Tuesdays x 2 courts - 1 taken
    assert_select "dd", text: "1"
    assert_select "span.line-through", text: /27\/10\/2026 · Sân 2/
    assert_select "span", text: /Khung giờ này đã có người đặt/

    assert_difference "Booking.count", 7 do
      post admin_series_index_path, params: series_params
    end
    series = BookingSeries.last
    assert_redirected_to admin_series_path(series)
    assert_equal users(:an), series.user, "linked to the account with this phone"
    assert_equal [ 240_000 ], series.bookings.pluck(:total_amount_vnd).uniq # 2h at the weekday peak price
  end

  test "an agreed price replaces the price rules" do
    series = create_series(price_per_hour_vnd: 100_000)

    assert_equal [ 200_000 ], series.bookings.pluck(:total_amount_vnd).uniq
  end

  test "sessions do not count towards the 2 upcoming bookings, nor towards the cancellation lock" do
    series = create_series
    sign_in users(:an)

    assert_difference("Booking.count", 1) { post bookings_path, params: { booking: { slots: { "0" => slot(:court_one, "2026-10-21 06:00", 60) } } } }

    series.bookings.order(:starts_at).first(3).each { |b| patch cancel_booking_path(b) }
    assert_nil users(:an).reload.booking_locked_until
  end

  test "the customer skips one session: only that time is released" do
    series = create_series
    session = series.bookings.where(court: courts(:court_one)).order(:starts_at).first # two courts start together
    sign_in users(:an)

    get booking_path(session)
    assert_select "p", text: /buổi trong lịch cố định/
    assert_select "button", text: "Báo nghỉ buổi này"
    assert_select "a", text: "Đổi giờ", count: 0

    patch cancel_booking_path(session)
    session.reload
    assert session.cancelled?
    assert_equal BookingSeries::SKIPPED, session.cancellation_reason
    assert_equal 7, series.bookings.where.not(status: :cancelled).count

    get root_path(date: "2026-10-20")
    assert_select "button[data-court-name='Sân 1'][data-starts-label='18:00']", 1, "free for others again"
  end

  test "monthly billing, and a skipped session refunded only when someone else played it" do
    series = create_series
    october = series.billing(Date.new(2026, 10, 1))
    assert_equal 4 * 240_000, october.due_vnd

    post mark_paid_admin_series_path(series, month: "2026-10-01")
    assert october.paid?
    assert series.bookings.where(starts_at: ...at("2026-11-01 00:00")).all?(&:payment_paid?)

    skipped, unsold, resold_no_show = series.bookings.order(:starts_at, :court_id).first(3)
    [ skipped, unsold, resold_no_show ].each { |b| b.cancel!(by: users(:an)) }
    # Someone else plays half of the first skipped session; the third one is resold to a no-show.
    courts(skipped.court.id == courts(:court_one).id ? :court_one : :court_two).bookings
      .create!(user: users(:chi), starts_at: skipped.starts_at, ends_at: skipped.starts_at + 1.hour)
    other = Court.find(resold_no_show.court_id).bookings.create!(source: :phone, customer_name: "Khách lẻ", customer_phone: "0912000111",
                                                                 starts_at: resold_no_show.starts_at, ends_at: resold_no_show.ends_at)
    other.update!(status: :no_show) # recorded before no-shows were dropped: not played

    travel_to at("2026-10-28 00:00")
    Series::Refunds.settle_due
    assert_equal [ 120_000, 0, 0 ], [ skipped, unsold, resold_no_show ].map { |b| b.reload.series_refund_vnd }
    assert skipped.payment_refunded?

    november = series.billing(Date.new(2026, 11, 1))
    assert_equal [ 4 * 240_000, 120_000, 4 * 240_000 - 120_000 ], [ november.amount_vnd, november.credit_vnd, november.due_vnd ]
    november.mark_paid!(by: users(:owner))
    assert_equal november.period, skipped.reload.series_refund_period
    assert_equal 0, series.billing(Date.new(2026, 12, 1)).credit_vnd, "a refund is taken off once"
  end

  test "a skipped session of an unpaid month is simply not billed" do
    series = create_series
    session = series.bookings.order(:starts_at).first
    session.cancel!(by: users(:an))

    travel_to at("2026-10-21 00:00")
    Series::Refunds.settle_due
    assert_equal 0, session.reload.series_refund_vnd
    assert_equal 3 * 240_000, series.billing(Date.new(2026, 10, 1)).amount_vnd
  end

  test "venue closed: sessions cancelled in a range and refunded in full; then the day can be blocked" do
    series = create_series
    series.billing(Date.new(2026, 10, 1)).mark_paid!(by: users(:owner))

    post close_range_admin_series_path(series, from: "2026-10-27", to: "2026-10-27")
    closed = series.bookings.where(starts_at: at("2026-10-27 18:00"))
    assert_equal [ BookingSeries::VENUE_CLOSED ], closed.pluck(:cancellation_reason).uniq
    courts(:court_one).bookings.create!(kind: :block, starts_at: at("2026-10-27 05:00"), ends_at: at("2026-10-27 22:00"))

    travel_to at("2026-10-28 00:00")
    Series::Refunds.settle_due
    assert_equal [ 240_000 ], closed.reload.pluck(:series_refund_vnd).uniq
  end

  test "extends, reprices future unpaid sessions and ends early without refund" do
    series = create_series
    series.billing(Date.new(2026, 10, 1)).mark_paid!(by: users(:owner))

    post extend_admin_series_path(series, ends_on: "2026-11-24")
    assert_equal 12, series.bookings.count # + 2 Tuesdays x 2 courts

    patch update_price_admin_series_path(series, price_per_hour_vnd: 100_000)
    prices = series.bookings.reload.order(:starts_at).map { |b| [ b.starts_at.month, b.total_amount_vnd ] }.uniq
    assert_equal [ [ 10, 240_000 ], [ 11, 200_000 ] ], prices, "October is paid, so its sessions keep their price"

    post end_from_admin_series_path(series, date: "2026-11-10")
    ended = series.bookings.where(starts_at: at("2026-11-10 00:00")..)
    assert_equal [ BookingSeries::ENDED ], ended.pluck(:cancellation_reason).uniq
    assert_equal Date.new(2026, 11, 9), series.reload.ends_on
  end

  test "staff manage regular bookings too" do
    sign_in users(:staffer)
    get admin_series_index_path
    assert_response :success
    get new_admin_series_path
    assert_response :success
  end

  private

  def at(time) = Time.zone.parse(time)

  def series_params(**overrides)
    { booking_series: { customer_name: "Nguyễn An", customer_phone: "0901 234 567", court_ids: [ "", courts(:court_one).id, courts(:court_two).id ],
                        days_of_week: [ "", "2" ], start_minute: 1080, end_minute: 1200, starts_on: "2026-10-20", ends_on: "2026-11-10",
                        price_per_hour_vnd: "" }.merge(overrides) }
  end

  def create_series(**overrides)
    post admin_series_index_path, params: series_params(**overrides)
    BookingSeries.last
  end

  def slot(court, from, minutes)
    { court_id: courts(court).id, starts_at: at(from).iso8601, ends_at: (at(from) + minutes.minutes).iso8601 }
  end
end
