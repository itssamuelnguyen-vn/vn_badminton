require "test_helper"

# Moving the sessions to come of a weekly booking to other courts or another time (Series::Move).
class SeriesMoveTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00") # Monday
    sign_in users(:owner)
  end

  test "plans the move without changing anything, then moves the sessions to come; paid months keep their amount" do
    series = create_series(days: [ 2 ], from: "2026-10-20", to: "2026-11-10") # Tuesdays 18:00-20:00 on court 1: 240.000đ
    post mark_paid_admin_series_path(series, month: "2026-10-01")
    travel_to Time.zone.parse("2026-10-21 09:00") # the session of 20/10 is over
    reset! # a new session: the owner's one timed out (TK-06)
    sign_in users(:staffer) # staff can move a series too

    get move_admin_series_path(series)
    assert_response :success
    assert_select "input[name='move[court_ids][]'][checked][value=?]", courts(:court_one).id.to_s
    assert_select "form[data-turbo=false][action=?]", move_admin_series_path(series)

    assert_no_changes -> { series.bookings.order(:id).pluck(:court_id, :starts_at, :total_amount_vnd) } do
      post move_admin_series_path(series), params: move_params(courts: [ :court_two ], days: [ 3 ], start: 360, finish: 480)
    end
    assert_response :success
    assert_select "dd", text: "3" # 3 sessions to move, no conflict
    assert_select "li", text: /27\/10\/2026 · Sân 1 · 18:00 – 20:00.*28\/10\/2026 · Sân 2 · 06:00 – 08:00.*240.000đ \(tháng đã đóng, giữ giá\)/m
    assert_select "li", text: /03\/11\/2026 · Sân 1.*04\/11\/2026 · Sân 2 · 06:00 – 08:00.*240.000đ → 160.000đ/m

    patch move_admin_series_path(series), params: move_params(courts: [ :court_two ], days: [ 3 ], start: 360, finish: 480)
    assert_redirected_to admin_series_path(series)
    assert_equal "Đã đổi giờ 3 buổi.", flash[:notice]

    sessions = series.bookings.order(:starts_at).map { |b| [ b.court.name, b.starts_at, b.total_amount_vnd, b.payment_status ] }
    assert_equal [ [ "1", at("2026-10-20 18:00"), 240_000, "paid" ], [ "2", at("2026-10-28 06:00"), 240_000, "paid" ],
                   [ "2", at("2026-11-04 06:00"), 160_000, "unpaid" ], [ "2", at("2026-11-11 06:00"), 160_000, "unpaid" ] ], sessions
    assert_equal 2 * 160_000, series.billing(Date.new(2026, 11, 1)).due_vnd
    series.reload
    assert_equal [ [ courts(:court_two).id ], [ 3 ], 360, 480 ], [ series.court_ids, series.days_of_week, series.start_minute, series.end_minute ]

    moved = series.bookings.find_by!(starts_at: at("2026-10-28 06:00"))
    assert_equal [ "rescheduled", users(:staffer) ], [ moved.events.last.action, moved.events.last.actor ]
    get admin_booking_path(moved)
    assert_select "li", text: /Đổi giờ: Sân 1 · 27\/10\/2026 18:00 – 20:00 → Sân 2 · 28\/10\/2026 06:00 – 08:00/
  end

  test "a conflict is skipped (the session stays) or moved to another free court, as chosen" do
    series = create_series(days: [ 2 ], from: "2026-10-20", to: "2026-11-03")
    taken = book_other(:court_two, "2026-10-27 06:00", "2026-10-27 07:00")
    params = move_params(courts: [ :court_two ], days: [ 2 ], start: 360, finish: 480)

    post move_admin_series_path(series), params: params
    first, second = series.bookings.order(:starts_at).first(2)
    assert_select "li", text: /27\/10\/2026.*Giờ mới đã có người đặt/m
    assert_equal [ "Giữ giờ cũ (không đổi buổi này)", "Đổi sang Sân 1" ], options(second)
    assert_select "select[name='choices[#{first.id}]']", 0

    perform_enqueued_jobs { patch move_admin_series_path(series), params: params.merge(choices: { second.id => "skip" }) }
    assert_redirected_to admin_series_path(series)
    mail = ActionMailer::Base.deliveries.last # the customer hears what moved and what stayed (CD-11)
    assert_equal [ [ users(:an).email ], "Lịch cố định của bạn đã đổi giờ (2 buổi)" ], [ mail.to, mail.subject ]
    assert_match(/Sân 1 · Thứ ba, 20\/10\/2026 · 18:00 – 20:00 → Sân 2 · Thứ ba, 20\/10\/2026 · 06:00 – 08:00/, mail.body.encoded)
    assert_match "1 buổi khác vẫn giữ giờ cũ.", mail.body.encoded
    assert_equal [ courts(:court_one), at("2026-10-27 18:00") ], [ second.reload.court, second.starts_at ], "kept its old slot"
    assert_equal [ courts(:court_two), at("2026-10-20 06:00") ], [ first.reload.court, first.starts_at ]

    # Later 07:00-09:00, but someone booked court 2 at 08:00 on 03/11: that session goes to court 1 instead.
    taken.cancel!(by: users(:owner))
    book_other(:court_two, "2026-11-03 08:00", "2026-11-03 09:00")
    third = series.bookings.find_by!(starts_at: at("2026-11-03 06:00"))
    post move_admin_series_path(series), params: move_params(courts: [ :court_two ], days: [ 2 ], start: 420, finish: 540)
    assert_equal [ "Giữ giờ cũ (không đổi buổi này)", "Đổi sang Sân 1" ], options(third)

    patch move_admin_series_path(series), params: move_params(courts: [ :court_two ], days: [ 2 ], start: 420, finish: 540)
                                                    .merge(choices: { third.id => courts(:court_one).id })
    assert_redirected_to admin_series_path(series)
    assert_equal [ courts(:court_one), at("2026-11-03 07:00") ], [ third.reload.court, third.starts_at ]
  end

  test "a slot taken after the plan was shown stops the whole move until it is resolved" do
    series = create_series(days: [ 2 ], from: "2026-10-20", to: "2026-11-03")
    params = move_params(courts: [ :court_two ], days: [ 2 ], start: 360, finish: 480)
    post move_admin_series_path(series), params: params
    book_other(:court_two, "2026-11-03 07:00", "2026-11-03 08:00")

    assert_no_changes -> { series.bookings.order(:id).pluck(:court_id, :starts_at) } do
      patch move_admin_series_path(series), params: params
    end
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Còn buổi bị trùng chưa chọn cách xử lý/
    assert_select "select[name^=choices]", 1
  end

  test "every court shifted by one: a session may take the court its neighbour leaves" do
    court_three = venues(:phu_nhuan).courts.create!(name: "3", position: 3)
    series = create_series(days: [ 2 ], from: "2026-10-20", to: "2026-10-27", courts: %i[court_one court_two])
    params = move_params(courts: [], days: [ 2 ], start: 1080, finish: 1200)
    params[:move][:court_ids] = [ courts(:court_two).id, court_three.id ]

    post move_admin_series_path(series), params: params
    assert_select "select[name^=choices]", 0

    patch move_admin_series_path(series), params: params
    assert_redirected_to admin_series_path(series)
    assert_equal [ [ "2", "3" ] ] * 2, series.bookings.includes(:court).group_by(&:starts_at).values.map { |list| list.map { |b| b.court.name }.sort }
  end

  test "a new day in another month, or no real change, is refused" do
    series = create_series(days: [ 1 ], from: "2026-10-26", to: "2026-11-09") # Mondays
    post move_admin_series_path(series), params: move_params(courts: [ :court_one ], days: [ 0 ], start: 1080, finish: 1200) # to Sundays
    first = series.bookings.find_by!(starts_at: at("2026-10-26 18:00"))
    assert_select "li", text: /26\/10\/2026.*01\/11\/2026.*Giờ mới sang tháng khác/m
    assert_equal [ "Giữ giờ cũ (không đổi buổi này)" ], options(first), "another court would not help"

    post move_admin_series_path(series), params: move_params(courts: [ :court_one ], days: [ 1 ], start: 1080, finish: 1200)
    assert_response :unprocessable_content
    assert_select "li", text: "Sân, ngày và giờ mới giống hệt lịch hiện tại."

    post move_admin_series_path(series), params: move_params(courts: %i[court_one court_two], days: [ 1 ], start: 1080, finish: 1200)
    assert_select "li", text: "Sân mới phải chọn đúng 1 (bằng lịch hiện tại)"
  end

  private

  def at(time) = Time.zone.parse(time)

  def create_series(days:, from:, to:, courts: %i[court_one])
    post admin_series_index_path, params: { booking_series: {
      customer_name: "Nguyễn An", customer_phone: "0901 234 567", court_ids: courts.map { |c| courts(c).id }, days_of_week: days,
      start_minute: 1080, end_minute: 1200, starts_on: from, ends_on: to, price_per_hour_vnd: "" } }
    BookingSeries.last
  end

  def book_other(court, from, to)
    courts(court).bookings.create!(source: :phone, customer_name: "Lê Chi", customer_phone: "0933000111", starts_at: at(from), ends_at: at(to))
  end

  def options(booking)
    css_select("select[name='choices[#{booking.id}]'] option").map(&:text)
  end

  def move_params(courts:, days:, start:, finish:, from: Time.current.to_date.iso8601)
    { move: { from: from, court_ids: [ "" ] + courts.map { |c| courts(c).id }, days_of_week: [ "" ] + days, start_minute: start, end_minute: finish } }
  end
end
