require "test_helper"

class Schedule::CalendarTest < ActiveSupport::TestCase
  setup do
    @venue = venues(:phu_nhuan) # 14-day booking horizon, open every day
    travel_to Time.zone.parse("2026-10-20 10:00")
  end

  test "dates from today to the horizon are selectable, others are not" do
    calendar = Schedule::Calendar.new(venue: @venue, selected: Date.new(2026, 10, 20))

    assert calendar.selectable?(Date.new(2026, 10, 20))
    assert calendar.selectable?(Date.new(2026, 11, 3))
    assert_not calendar.selectable?(Date.new(2026, 10, 19)), "past"
    assert_not calendar.selectable?(Date.new(2026, 11, 4)), "beyond the horizon"
  end

  test "closed days and today after closing are not selectable" do
    opening_hours(:phu_nhuan_3).destroy # Wednesdays

    calendar = Schedule::Calendar.new(venue: @venue, selected: Date.new(2026, 10, 20), now: Time.zone.parse("2026-10-20 21:45"))

    assert_not calendar.selectable?(Date.new(2026, 10, 21)), "closed on Wednesday"
    assert_not calendar.selectable?(Date.new(2026, 10, 20)), "no slot left today"
    assert_equal Date.new(2026, 10, 22), calendar.first_selectable
  end

  test "previous and next selectable dates skip unselectable days" do
    opening_hours(:phu_nhuan_3).destroy

    calendar = Schedule::Calendar.new(venue: @venue, selected: Date.new(2026, 10, 22))

    assert_equal Date.new(2026, 10, 20), calendar.previous_selectable
    assert_equal Date.new(2026, 10, 23), calendar.next_selectable
    assert_nil Schedule::Calendar.new(venue: @venue, selected: Date.new(2026, 10, 20)).previous_selectable
  end

  test "months cover the booking horizon and weeks start on Monday" do
    calendar = Schedule::Calendar.new(venue: @venue, selected: Date.new(2026, 10, 20))

    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 11, 1) ], calendar.months
    weeks = calendar.weeks(Date.new(2026, 10, 1))
    assert_equal Date.new(2026, 9, 28), weeks.first.first
    assert weeks.all? { |week| week.size == 7 && week.first.monday? }
    assert_equal Date.new(2026, 11, 1), weeks.last.last
  end
end
