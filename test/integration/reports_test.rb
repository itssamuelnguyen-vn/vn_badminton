require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    # 2 courts open 05:00-22:00 = 2 x 17h = 2040 court-minutes a day.
    paid = book(:court_one, "2026-10-20 18:00", 90)
    paid.mark_paid!
    book(:court_two, "2026-10-20 18:00", 60)
    book(:court_one, "2026-10-21 06:00", 60).cancel!(by: users(:an))
    book(:court_one, "2026-11-02 18:00", 60) # next month
  end

  test "monthly revenue and occupancy for the owner" do
    sign_in users(:owner)
    get admin_reports_path(month: "2026-10")

    assert_response :success
    assert_select "dd", text: "300.000đ" # 180.000 + 120.000
    assert_select "dd", text: "180.000đ" # collected
    row = css_select("tbody tr").find { |tr| tr.text.include?("20/10/2026") }
    assert_includes row.text, "2h30"
    assert_includes row.text, "7,4%" # 150 / 2040
    cells = css_select("tbody tr").find { |tr| tr.text.include?("21/10/2026") }.css("td").map { |td| td.text.strip }
    assert_equal [ "0", "0h", "0%", "0đ", "0đ", "0", "1" ], cells.drop(1) # only a cancelled booking that day
    assert_select "li[title^='18:00 – 19:00']", text: /3,2%/ # 120 booked minutes / (31 days x 2 courts x 60)
  end

  test "exports the month's reservations as CSV" do
    sign_in users(:owner)
    get admin_reports_path(month: "2026-10", format: :csv)

    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    lines = response.body.delete_prefix("﻿").lines
    assert_equal 4, lines.size # header + 3 bookings of October (the cancelled one included, with its status)
    assert_match(/\A[A-Z0-9]{8},2026-10-20,Sân 1,18:00,19:30,Nguyễn An,0901 234 567,online,confirmed,paid,180000/, lines[1])
  end

  test "staff cannot see reports" do
    sign_in users(:staffer)
    get admin_reports_path
    assert_redirected_to admin_root_path
  end

  private

  def book(court, from, minutes)
    starts_at = Time.zone.parse(from)
    courts(court).bookings.create!(user: users(:an), source: :phone, customer_name: "Nguyễn An", customer_phone: "0901234567",
                                   starts_at: starts_at, ends_at: starts_at + minutes.minutes).tap { |b| b.update_column(:source, "online") }
  end
end
