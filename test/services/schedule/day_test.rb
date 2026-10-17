require "test_helper"

class Schedule::DayTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.parse("2026-10-20 10:00") # Tuesday
    @venue = venues(:phu_nhuan)
    @court = courts(:court_one)
  end

  test "lists 30-minute slots from opening to closing" do
    day = Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 21))

    assert_equal 34, day.times.size
    assert_equal Time.zone.parse("2026-10-21 05:00"), day.times.first
    assert_equal Time.zone.parse("2026-10-21 21:30"), day.times.last
  end

  test "marks booked, own, blocked, past and available slots" do
    owner = users(:owner)
    @court.bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))
    courts(:court_two).bookings.create!(kind: :block, created_by: owner, starts_at: at("11:00"), ends_at: at("12:00"))

    day = Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 20), user: users(:an))
    other = Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 20), user: owner)

    assert_equal :mine, day.slot(@court, at("18:30")).state
    assert_equal :booked, other.slot(@court, at("18:30")).state
    assert_equal :blocked, day.slot(courts(:court_two), at("11:00")).state
    assert_equal :unavailable, day.slot(@court, at("09:30")).state
    assert_equal :available, day.slot(@court, at("19:00")).state
  end

  test "is not bookable once its last slot has started" do
    assert Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 20), now: at("21:29")).bookable?
    assert_not Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 20), now: at("21:31")).bookable?
  end

  test "prices each slot with the matching rule" do
    day = Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 20))

    assert_equal 40_000, day.slot(@court, at("12:00")).price_vnd
    assert_equal 60_000, day.slot(@court, at("18:00")).price_vnd
  end

  test "has no slots on a day without opening hours" do
    opening_hours(:phu_nhuan_3).destroy

    day = Schedule::Day.new(venue: @venue, date: Date.new(2026, 10, 21))

    assert_not day.open?
    assert_empty day.times
  end

  private

  def at(hhmm)
    Time.zone.parse("2026-10-20 #{hhmm}")
  end
end
