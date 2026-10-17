require "test_helper"

class PhoneNumberTest < ActiveSupport::TestCase
  test "normalizes Vietnamese numbers to E.164" do
    assert_equal "+84901234567", PhoneNumber.normalize("0901 234 567")
    assert_equal "+84901234567", PhoneNumber.normalize("84901234567")
    assert_equal "+84901234567", PhoneNumber.normalize("+84 90-123-4567")
  end

  test "leaves invalid numbers for validation to reject" do
    assert_nil PhoneNumber.normalize(" ")
    assert_no_match PhoneNumber::FORMAT, PhoneNumber.normalize("12345")
  end
end
