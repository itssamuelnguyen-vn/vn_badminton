require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeds the venue and can run twice without duplicating anything" do
    2.times { assert_output(/Seeded VN Badminton/) { Rails.application.load_seed } }

    venue = Venue.find_by!(slug: "vn-badminton")
    assert_equal 10, venue.courts.count
    assert_equal 7, venue.opening_hours.count
    assert_equal 3, venue.price_rules.count
  end
end
