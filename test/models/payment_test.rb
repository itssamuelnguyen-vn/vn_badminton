require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  test "the code pattern accepts exactly the prefix and the booking code characters" do
    assert_equal "VNB", Payment::CODE_PREFIX
    assert_equal Booking::CODE_CHARS.sort, ([ *"A".."Z", *"0".."9" ].select { |c| "VNB#{c * 8}".match?(Payment::CODE_PATTERN) }).sort
  end

  test "finds the code in a transfer content, whatever the case and the surrounding text" do
    assert_equal "VNB7K2QH9XA", Payment.code_in("NGUYEN VAN A chuyen tien vnb7k2qh9xa san cau long")
    assert_nil Payment.code_in("chuyen tien san 18h")
  end

  test "generates a unique code and token, and builds the VietQR image" do
    payment = Payment.create!(purpose: :bookings, amount_vnd: 120_000, expires_at: 15.minutes.from_now)

    assert_match(/\AVNB[A-HJ-NP-Z2-9]{8}\z/, payment.code)
    assert_operator payment.token.size, :>=, 20
    url = payment.qr_url(venues(:phu_nhuan))
    assert_includes url, "acc=0123456789"
    assert_includes url, "amount=120000"
    assert_includes url, "des=#{payment.code}"
  end

  test "stays payable for a grace period after the deadline" do
    freeze_time
    payment = Payment.new(status: :awaiting, expires_at: Time.current)

    assert payment.open?(Time.current + Payment::GRACE)
    assert_not payment.open?(Time.current + Payment::GRACE + 1.second)
  end
end
