require "test_helper"

class OpeningHourTest < ActiveSupport::TestCase
  test "converts between HH:MM and minutes since midnight" do
    assert_equal 330, OpeningHour.parse_minute("05:30")
    assert_equal "05:30", OpeningHour.format_minute(330)
    assert_equal "24:00", OpeningHour.format_minute(1440)
  end

  test "covers a range inside opening hours" do
    hours = opening_hours(:phu_nhuan_2)

    assert hours.covers?(300, 1320)
    assert_not hours.covers?(1290, 1350)
  end
end
