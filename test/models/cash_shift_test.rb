require "test_helper"

# The cash drawer per shift: expected = opening + cash recorded while the shift is open (see CashShift).
class CashShiftTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @venue = venues(:phu_nhuan)
    Current.user = users(:staffer)
  end

  teardown { Current.reset }

  test "one open shift at a time" do
    first = CashShift.open!(venue: @venue, by: users(:staffer), opening_vnd: 500_000)
    assert first.persisted?

    second = CashShift.open!(venue: @venue, by: users(:owner), opening_vnd: 0)
    assert_not second.persisted?
    assert second.errors.of_kind?(:base, :already_open)
    assert_raises(ActiveRecord::RecordNotUnique) do
      CashShift.insert!({ venue_id: @venue.id, opened_by_id: users(:owner).id, opened_at: Time.current, opening_vnd: 0 })
    end
  end

  test "expected = opening + cash paid at the counter, at what the customer paid (products included)" do
    shift = open_shift(500_000)
    walk_in = book("2026-10-19 18:00") # 1h peak: 120.000đ
    walk_in.update_columns(items_amount_vnd: 30_000)
    walk_in.mark_paid!
    by_transfer = book("2026-10-19 19:00")
    by_transfer.update!(payment: Payment.create!(purpose: :bookings, amount_vnd: 120_000, expires_at: 10.minutes.from_now))
    by_transfer.mark_paid!

    assert_equal 150_000, shift.collected_vnd
    assert_equal 650_000, shift.expected_vnd
    assert_nil by_transfer.events.last.cash_shift_id, "a transfer never reaches the drawer"
  end

  test "a payment undone in the same shift cancels out; paid again counts once" do
    shift = open_shift(0)
    booking = book("2026-10-19 18:00")
    booking.mark_paid!
    booking.undo_payment!
    assert_equal 0, shift.collected_vnd

    booking.mark_paid!
    assert_equal 120_000, shift.collected_vnd
    assert_equal [ 120_000, -120_000, 120_000 ], shift.events.order(:id).pluck(:cash_vnd)
  end

  test "undoing a payment of an earlier shift leaves both shifts as they were counted" do
    first = open_shift(0)
    booking = book("2026-10-19 18:00")
    booking.mark_paid!
    assert first.close!(by: users(:staffer), counted_vnd: 120_000, note: nil)

    second = open_shift(120_000)
    booking.undo_payment!
    assert_equal 0, second.collected_vnd, "not taken off the next shift"
    assert_equal [ 120_000, 120_000, 120_000, 0 ], first.reload.values_at(:collected_vnd, :expected_vnd, :counted_vnd, :difference_vnd)
  end

  test "cash recorded with no shift open belongs to no shift" do
    booking = book("2026-10-19 18:00")
    booking.mark_paid!
    shift = open_shift(0)
    booking.undo_payment!

    assert_equal 0, shift.collected_vnd
    assert_equal [ nil, nil ], booking.events.where(action: %w[paid payment_undone]).pluck(:cash_vnd)
  end

  test "a series month paid in cash counts its due amount; paid by transfer it does not" do
    shift = open_shift(0)
    series = BookingSeries.create!(customer_name: "Khách quen", customer_phone: "0912000111", created_by: users(:owner),
                                   court_ids: [ courts(:court_one).id ], days_of_week: [ 2 ], start_minute: 1080, end_minute: 1200,
                                   starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 11, 30))
    Series::Planner.new(series, from: series.starts_on, to: series.ends_on, by: users(:owner)).create!

    series.billing(Date.new(2026, 10, 1)).mark_paid!(by: users(:staffer), cash: true) # 2 Tuesdays x 240.000đ
    series.billing(Date.new(2026, 11, 1)).mark_paid!(by: users(:staffer))

    assert_equal 480_000, shift.collected_vnd
    assert_kind_of Integer, shift.collected_vnd
    assert_equal [ shift.id, nil ], series.periods.order(:month).pluck(:cash_shift_id)
    assert_empty shift.events, "the sessions' own 'paid' events are not cash"
  end

  test "closing stores the count and the difference; a difference needs a note" do
    shift = open_shift(200_000)
    book("2026-10-19 18:00").mark_paid!

    assert_not shift.close!(by: users(:staffer), counted_vnd: 300_000, note: " ")
    assert shift.errors.of_kind?(:note, :blank)
    assert_not shift.reload.closed?

    assert shift.close!(by: users(:staffer), counted_vnd: 300_000, note: "Thối nhầm 20.000đ")
    shift.reload
    assert_equal [ 120_000, 320_000, 300_000, -20_000 ], shift.values_at(:collected_vnd, :expected_vnd, :counted_vnd, :difference_vnd)
    assert_equal users(:staffer), shift.closed_by

    assert_not shift.close!(by: users(:owner), counted_vnd: 0, note: "x")
    assert shift.errors.of_kind?(:base, :already_closed)
  end

  test "cash recorded after the close goes to no shift" do
    shift = open_shift(0)
    assert shift.close!(by: users(:staffer), counted_vnd: 0, note: nil)
    book("2026-10-19 18:00").mark_paid!

    assert_equal 0, shift.reload.collected_vnd
  end

  test "the database requires a note for a difference and consistent amounts" do
    shift = open_shift(100_000)
    closed = { closed_at: Time.current, closed_by_id: users(:owner).id, collected_vnd: 0, expected_vnd: 100_000, counted_vnd: 90_000 }

    assert_raises(ActiveRecord::StatementInvalid) { shift.update_columns(closed.merge(difference_vnd: -10_000)) }
    assert_raises(ActiveRecord::StatementInvalid) { shift.update_columns(closed.merge(difference_vnd: 0, note: "x")) }
  end

  private

  def open_shift(amount)
    CashShift.open!(venue: @venue, by: users(:staffer), opening_vnd: amount).tap { |shift| assert shift.persisted? }
  end

  def book(from)
    starts_at = Time.zone.parse(from)
    courts(:court_one).bookings.create!(source: :walk_in, customer_name: "Khách lẻ", customer_phone: "0912000111",
                                        starts_at: starts_at, ends_at: starts_at + 1.hour, created_by: users(:staffer))
  end
end
