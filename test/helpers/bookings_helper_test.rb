require "test_helper"

class BookingsHelperTest < ActionView::TestCase
  test "formats VND amounts per locale" do
    I18n.with_locale(:vi) { assert_equal "180.000đ", format_vnd(180_000) }
    I18n.with_locale(:en) { assert_equal "180,000 VND", format_vnd(180_000) }
  end

  test "formats durations" do
    assert_equal "1h30", format_duration(90)
    assert_equal "2h", format_duration(120)
  end

  test "formats days of the week Monday first, collapsing runs into ranges" do
    I18n.with_locale(:vi) do
      assert_equal "Hằng ngày", format_days((0..6).to_a)
      assert_equal "Thứ 2 – Thứ 6", format_days([ 5, 1, 2, 3, 4 ])
      assert_equal "Thứ 7, CN", format_days([ 0, 6 ])
      assert_equal "Thứ 2, Thứ 4", format_days([ 3, 1 ])
    end
  end
end
