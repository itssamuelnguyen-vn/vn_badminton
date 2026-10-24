require "test_helper"

class BookingTest < ActiveSupport::TestCase
  # Monday 2026-10-19 10:00 in Vietnam; bookings below are for Tuesday 2026-10-20.
  setup { travel_to Time.zone.parse("2026-10-19 10:00") }

  test "reserve prices the booking and assigns a code" do
    booking = build_booking(starts_at: at("05:00"), ends_at: at("06:30"))

    assert booking.reserve, booking.errors.full_messages.to_sentence
    assert_equal 120_000, booking.total_amount_vnd
    assert_match(/\A[A-Z0-9]{8}\z/, booking.code)
    assert_equal "Nguyễn An", booking.customer_name
    assert_equal "+84901234567", booking.customer_phone
  end

  test "price breakdown splits standard and peak slots" do
    booking = build_booking(starts_at: at("17:00"), ends_at: at("19:00"))

    assert booking.reserve
    assert_equal 80_000 + 120_000, booking.total_amount_vnd
    assert_equal [ 80_000, 120_000 ], booking.price_breakdown.map { |line| line["amount_vnd"] }
  end

  test "rejects an overlapping booking on the same court" do
    assert build_booking.reserve

    clash = build_booking(starts_at: at("18:30"), ends_at: at("19:30"))
    assert_not clash.reserve
    assert clash.errors.added?(:base, :slot_taken)
  end

  test "allows back-to-back bookings and the same time on another court" do
    assert build_booking.reserve
    assert build_booking(starts_at: at("19:00"), ends_at: at("20:00")).reserve
    assert build_booking(court: courts(:court_two)).reserve
  end

  test "turns an exclusion constraint violation into a friendly error" do
    assert build_booking.reserve

    clash = build_booking
    clash.define_singleton_method(:slot_free) { } # simulate a request that passed the soft check
    assert_not clash.reserve
    assert clash.errors.added?(:base, :slot_just_taken)
  end

  test "rejects times off the 30-minute grid" do
    booking = build_booking(starts_at: at("18:15"), ends_at: at("19:15"))

    assert_not booking.reserve
    assert booking.errors.added?(:base, :off_slot_grid)
  end

  test "rejects bookings outside opening hours" do
    booking = build_booking(starts_at: at("21:30"), ends_at: at("22:30"))

    assert_not booking.reserve
    assert booking.errors.added?(:base, :outside_opening_hours)
  end

  test "rejects online bookings in the past" do
    booking = build_booking(starts_at: Time.zone.parse("2026-10-19 06:00"), ends_at: Time.zone.parse("2026-10-19 07:00"))

    assert_not booking.reserve
    assert booking.errors.added?(:starts_at, :not_in_future)
  end

  test "a customer cannot cancel after the cutoff, a manager can" do
    booking = reserve!

    travel_to at("17:00") do
      assert_raises(ArgumentError) { booking.cancel!(by: users(:an)) }
      booking.cancel!(by: users(:owner), reason: "Khách gọi báo")
    end

    assert booking.reload.cancelled?
    assert_equal users(:owner), booking.cancelled_by
  end

  test "a cancelled slot can be booked again and the old booking cannot be restored" do
    booking = reserve!
    booking.cancel!(by: users(:an))
    assert build_booking.reserve

    booking.status = :confirmed
    booking.cancelled_at = nil
    assert_not booking.reserve
    assert booking.errors.added?(:base, :slot_taken)
  end

  test "a block defaults to the staff source and keeps customers out" do
    block = courts(:court_one).bookings.new(kind: :block, created_by: users(:owner), starts_at: at("06:00"), ends_at: at("12:00"))

    assert block.reserve, block.errors.full_messages.to_sentence
    assert block.source_staff?
    assert_equal 0, block.total_amount_vnd

    assert_not build_booking(starts_at: at("08:00"), ends_at: at("09:00")).reserve
  end

  test "error messages follow the current locale" do
    assert build_booking.reserve
    clash = build_booking
    clash.reserve

    I18n.with_locale(:vi) { assert_includes clash.errors.full_messages, "Khung giờ này đã có người đặt" }
    I18n.with_locale(:en) { assert_includes clash.errors.full_messages, "This slot is already booked" }
  end

  test "reports the local time of a slot without a price in each locale" do
    price_rules(:standard).update!(active: false)
    booking = build_booking(starts_at: at("06:00"), ends_at: at("07:00"))

    assert_not booking.reserve
    I18n.with_locale(:vi) { assert_includes booking.errors.full_messages, "Chưa có bảng giá cho khung 06:00 ngày 20/10/2026" }
  end

  test "a booking beyond the horizon gets a pluralized message" do
    booking = build_booking(starts_at: Time.zone.parse("2026-11-20 18:00"), ends_at: Time.zone.parse("2026-11-20 19:00"))

    assert_not booking.reserve
    I18n.with_locale(:vi) { assert_includes booking.errors.full_messages, "Giờ bắt đầu chỉ được đặt trước tối đa 14 ngày" }
    I18n.with_locale(:en) { assert_includes booking.errors.full_messages, "Start time can be at most 14 days in advance" }
  end

  private

  def at(hhmm)
    Time.zone.parse("2026-10-20 #{hhmm}")
  end

  def build_booking(court: courts(:court_one), starts_at: at("18:00"), ends_at: at("19:00"), **attrs)
    court.bookings.new(user: users(:an), source: :online, starts_at:, ends_at:, **attrs)
  end

  def reserve!(**attrs)
    build_booking(**attrs).tap { |booking| assert booking.reserve, booking.errors.full_messages.to_sentence }
  end
end
