require "test_helper"

# The owner's customer report: top customers, regulars gone quiet, no-show rates (Reports::Customers).
class CustomerReportsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
  end

  test "top customers of the month by court time and by amount" do
    book("0901234567", "Nguyễn An", "2026-10-05 06:00", 120)                   # 2h off-peak: 160.000đ
    book("0933000111", "Lê Chi", "2026-10-06 18:00", 60)                       # 1h peak: 120.000đ
    book("0933000111", "Lê Chi", "2026-10-07 18:00", 60)
    book("0933000111", "Lê Chi", "2026-10-08 18:00", 60, status: :cancelled)   # not counted
    book("0944555666", "Bình", "2026-09-20 06:00", 300)                        # previous month

    report = Reports::Customers.new(venue: venues(:phu_nhuan), month: Date.new(2026, 10, 1))
    assert_equal [ [ "Lê Chi", 120, 240_000 ], [ "Nguyễn An", 120, 160_000 ] ], report.top_by_amount.map { |r| [ r.name, r.minutes, r.amount_vnd ] }
    assert_equal "Lê Chi", report.top_by_hours.first.name, "same time: the one who spent more first"

    sign_in users(:owner)
    get admin_customer_reports_path(month: "2026-10")
    assert_response :success
    assert_select "a[aria-current=page]", text: "Báo cáo khách"
    assert_select "section[aria-labelledby=top-amount] li", 2
    assert_select "section[aria-labelledby=top-amount] li:first-child", text: /Lê Chi.*240.000đ/m

    get admin_customer_reports_path(month: "2026-10", months: 3)
    assert_select "section[aria-labelledby=top-hours] li:first-child", text: /Bình.*5h/m
    assert_select "span", text: "Tháng 8, 2026 – Tháng 10, 2026"
  end

  test "regulars who played 3 times and have not booked for 30 days, most recently seen first" do
    3.times { |i| book("0901234567", "Nguyễn An", "2026-08-#{10 + i} 06:00", 60, status: :completed) }
    3.times { |i| book("0933000111", "Lê Chi", "2026-09-0#{1 + i} 06:00", 60, status: :checked_in) }
    3.times { |i| book("0944555666", "Bình", "2026-09-0#{1 + i} 07:00", 60, status: :completed) }
    book("0944555666", "Bình", "2026-10-25 07:00", 60) # booked again: not lapsed
    2.times { |i| book("0912000111", "Hai lần", "2026-08-0#{1 + i} 06:00", 60, status: :completed) } # too few visits
    3.times { |i| book("0977000111", "Không đến", "2026-08-0#{1 + i} 08:00", 60, status: :no_show) }   # never played
    CustomerProfile.create!(phone: "0933000111").tap { |p| p.block(by: users(:owner), reason: "Nợ tiền") }.save!

    lapsed = Reports::Customers.new(venue: venues(:phu_nhuan), month: Date.new(2026, 10, 1)).lapsed
    assert_equal [ "Lê Chi", "Nguyễn An" ], lapsed.map(&:name)
    assert_equal [ 3, Time.zone.parse("2026-09-03 06:00") ], [ lapsed.first.visits, lapsed.first.last_visit_at ]

    sign_in users(:owner)
    get admin_customer_reports_path
    assert_select "section[aria-labelledby=lapsed] a[href='tel:+84933000111']", text: "0933 000 111"
    assert_select "section[aria-labelledby=lapsed] li", text: /Lê Chi.*Danh sách đen.*Lần cuối 03\/09\/2026 · 3 lượt/m
  end

  test "no-show rate per customer, highest first, linking to the customer page" do
    book("0901234567", "Nguyễn An", "2026-10-01 06:00", 60, status: :no_show)
    book("0901234567", "Nguyễn An", "2026-10-02 06:00", 60, status: :completed)
    book("0901234567", "Nguyễn An", "2026-10-25 06:00", 60) # not played yet: not counted
    book("0933000111", "Lê Chi", "2026-10-03 06:00", 60, status: :no_show)
    book("0933000111", "Lê Chi", "2026-10-04 06:00", 60, status: :cancelled)

    report = Reports::Customers.new(venue: venues(:phu_nhuan), month: Date.new(2026, 10, 1))
    assert_equal [ [ "Lê Chi", 1, 1 ], [ "Nguyễn An", 2, 1 ] ], report.no_shows.map { |r| [ r.name, r.ended, r.no_show_count ] }

    sign_in users(:owner)
    get admin_customer_reports_path(month: "2026-10")
    rows = css_select("section[aria-labelledby=no-shows] tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
    assert_equal [ "1", "1", "100%" ], rows.first.drop(1)
    assert_equal [ "2", "1", "50%" ], rows.second.drop(1)
    assert_select "section[aria-labelledby=no-shows] a[href=?]", admin_customer_path("0933000111"), text: "Lê Chi"
  end

  test "only the owner" do
    sign_in users(:staffer)
    get admin_customer_reports_path

    assert_redirected_to admin_root_path
  end

  private

  def book(phone, name, from, minutes, status: :confirmed)
    starts_at = Time.zone.parse(from)
    booking = Court.find_by!(name: starts_at.min.zero? && starts_at.hour == 7 ? "2" : "1").bookings
                   .create!(source: :phone, customer_name: name, customer_phone: phone, starts_at: starts_at, ends_at: starts_at + minutes.minutes)
    extra = { checked_in_at: (starts_at if status.in?(%i[checked_in completed])), cancelled_at: (starts_at if status == :cancelled) }
    booking.update_columns(status: status.to_s, **extra.compact)
    booking
  end
end
