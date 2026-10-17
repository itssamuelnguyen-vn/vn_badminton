require "test_helper"

class BookingMailerTest < ActionMailer::TestCase
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-20 18:00"),
                                                   ends_at: Time.zone.parse("2026-10-20 19:30"))
  end

  test "confirmation email in Vietnamese" do
    mail = BookingMailer.with(booking: @booking, locale: :vi).confirmed

    assert_equal [ "an@example.com" ], mail.to
    assert_equal "Xác nhận đặt sân #{@booking.code}", mail.subject
    assert_includes mail.body.to_s, "18:00 – 19:30"
    assert_includes mail.body.to_s, "180.000đ"
    assert_includes mail.body.to_s, "http://example.com/bookings/#{@booking.code}"
  end

  test "confirmation email in English keeps the /en prefix" do
    mail = BookingMailer.with(booking: @booking, locale: :en).confirmed

    assert_equal "Booking confirmed: #{@booking.code}", mail.subject
    assert_includes mail.body.to_s, "180,000 VND"
    assert_includes mail.body.to_s, "http://example.com/en/bookings/#{@booking.code}"
  end
end
