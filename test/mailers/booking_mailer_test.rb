require "test_helper"

class BookingMailerTest < ActionMailer::TestCase
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @booking = book(:court_one, "18:00", "19:30")
  end

  test "confirmation email in Vietnamese" do
    mail = BookingMailer.with(bookings: [ @booking ], locale: :vi).confirmed

    assert_equal [ "an@example.com" ], mail.to
    assert_equal "Xác nhận đặt sân #{@booking.code}", mail.subject
    assert_includes mail.body.to_s, "18:00 – 19:30"
    assert_includes mail.body.to_s, "180.000đ"
    assert_includes mail.body.to_s, "http://example.com/bookings/#{@booking.code}"
  end

  test "confirmation email in English keeps the /en prefix" do
    mail = BookingMailer.with(bookings: [ @booking ], locale: :en).confirmed

    assert_equal "Booking confirmed: #{@booking.code}", mail.subject
    assert_includes mail.body.to_s, "180,000 VND"
    assert_includes mail.body.to_s, "http://example.com/en/bookings/#{@booking.code}"
  end

  test "one email lists every court booked together" do
    other = book(:court_two, "19:00", "21:00")

    mail = BookingMailer.with(bookings: [ @booking, other ], locale: :vi).confirmed

    assert_equal "Xác nhận đặt sân #{@booking.code}, #{other.code}", mail.subject
    assert_includes mail.body.to_s, "(2 sân)"
    assert_includes mail.body.to_s, "420.000đ"
  end

  private

  def book(court, from, to)
    courts(court).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-20 #{from}"), ends_at: Time.zone.parse("2026-10-20 #{to}"))
  end
end
