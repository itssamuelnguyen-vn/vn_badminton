require "test_helper"

class VenueTest < ActiveSupport::TestCase
  test "the Facebook page is kept as its username or id, also when its address is pasted" do
    venue = venues(:phu_nhuan)
    {
      "https://www.facebook.com/vnbadminton/" => "vnbadminton",
      "fb.com/san.cau.long" => "san.cau.long",
      "https://m.me/vnbadminton" => "vnbadminton",
      "https://www.facebook.com/profile.php?id=61550000000000" => "61550000000000",
      " vnbadminton " => "vnbadminton",
      "" => nil
    }.each do |input, kept|
      venue.facebook_page = input
      kept ? assert_equal(kept, venue.facebook_page, input) : assert_nil(venue.facebook_page, input)
    end

    venue.facebook_page = "facebook.com/groups/abc"
    assert_not venue.valid?
  end

  test "contact links only for the channels filled in" do
    venue = venues(:phu_nhuan)
    assert_equal({}, venue.contact_links)

    venue.assign_attributes(zalo_phone: "0901 234 567", facebook_page: "vnbadminton", phone: "0283 123 456")
    assert_equal({ zalo: "https://zalo.me/0901234567", messenger: "https://m.me/vnbadminton", phone: "tel:+84283123456" }, venue.contact_links)
  end
end
