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

  test "cancellation email when the customer cancels" do
    @booking.cancel!(by: users(:an))

    mail = BookingMailer.with(booking: @booking).cancelled

    assert_equal [ "an@example.com" ], mail.to
    assert_equal "Đã huỷ lượt đặt sân #{@booking.code}", mail.subject
    assert_includes mail.body.to_s, "đã được huỷ theo yêu cầu"
    assert_not_includes mail.body.to_s, "Xin lỗi"
  end

  test "cancellation email when the owner cancels, in the customer's language" do
    @booking.court.venue.update!(phone: "0283 123 456")
    users(:an).update!(locale: "en")
    @booking.cancel!(by: users(:owner))

    mail = BookingMailer.with(booking: @booking).cancelled

    assert_equal "Booking #{@booking.code} cancelled", mail.subject
    assert_includes mail.body.to_s, "The venue has cancelled your booking"
    assert_includes mail.body.to_s, "please call 0283 123 456"
    assert_includes mail.body.to_s, "http://example.com/en/bookings/#{@booking.code}"
  end

  test "reminder email" do
    mail = BookingMailer.with(booking: @booking).reminder

    assert_equal "Nhắc lịch: Sân 1 lúc 18:00 ngày 20/10/2026", mail.subject
    assert_includes mail.body.to_s, "Bạn có lịch chơi lúc 18:00 tại Sân 1"
    assert_includes mail.body.to_s, "12 Phan Xích Long"
    assert_includes mail.body.to_s, "Thanh toán tại sân"
  end

  test "confirmation email without a locale uses the customer's language" do
    users(:an).update!(locale: "en")

    mail = BookingMailer.with(bookings: [ @booking ]).confirmed

    assert_equal "Booking confirmed: #{@booking.code}", mail.subject
  end

  private

  def book(court, from, to)
    courts(court).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-20 #{from}"), ends_at: Time.zone.parse("2026-10-20 #{to}"))
  end
end
