require "test_helper"

class CourtTest < ActiveSupport::TestCase
  test "a numbered court is named in the current locale" do
    court = Court.new(name: "3")

    assert_equal "Sân 3", court.display_name
    I18n.with_locale(:en) { assert_equal "Court 3", court.display_name }
  end

  test "any other name is shown as entered" do
    assert_equal "VIP", Court.new(name: "VIP").display_name
  end
end
