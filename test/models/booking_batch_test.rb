require "test_helper"

class BookingBatchTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.parse("2026-10-19 10:00") }

  test "books several courts with their own time ranges" do
    batch = batch_for([ courts(:court_two), "19:00", "21:00" ], [ courts(:court_one), "18:00", "19:30" ])

    assert batch.reserve
    assert_equal [ courts(:court_one), courts(:court_two) ], batch.bookings.map(&:court), "sorted by court"
    assert batch.bookings.all?(&:persisted?)
    assert_equal 180_000 + 240_000, batch.total_amount_vnd
  end

  test "books nothing when one court is already taken" do
    courts(:court_two).bookings.create!(user: users(:chi), starts_at: at("19:00"), ends_at: at("20:00"))
    batch = batch_for([ courts(:court_one), "18:00", "19:30" ], [ courts(:court_two), "19:30", "21:00" ])

    assert_no_difference "Booking.count" do
      assert_not batch.reserve
    end
    assert batch.bookings.none?(&:persisted?)
    assert batch.bookings.last.errors.added?(:base, :slot_taken)
  end

  test "rolls back the earlier bookings when a later one hits the exclusion constraint" do
    batch = batch_for([ courts(:court_one), "18:00", "19:00" ], [ courts(:court_two), "18:00", "19:00" ])
    courts(:court_two).bookings.create!(user: users(:chi), starts_at: at("18:00"), ends_at: at("19:00"))
    batch.bookings.last.define_singleton_method(:slot_free) { } # simulate a request that passed the soft check

    assert_no_difference "Booking.count" do
      assert_not batch.reserve
    end
    assert batch.bookings.last.errors.added?(:base, :slot_just_taken)
  end

  test "validates every booking, not only up to the first failure" do
    batch = batch_for([ courts(:court_one), "21:30", "22:30" ], [ courts(:court_two), "18:00", "18:30" ])

    assert_not batch.valid?
    assert batch.bookings.first.errors.added?(:base, :outside_opening_hours)
    assert batch.bookings.last.errors.added?(:base, :duration_out_of_range, min: 60, max: 240)
  end

  test "rejects an unknown or inactive court" do
    courts(:court_two).update!(status: :inactive)

    assert_raises(ActiveRecord::RecordNotFound) { batch_for([ courts(:court_two), "18:00", "19:00" ]) }
  end

  private

  def batch_for(*ranges)
    slots = ranges.map { |court, from, to| { court_id: court.id.to_s, starts_at: at(from).iso8601, ends_at: at(to).iso8601 } }
    BookingBatch.new(user: users(:an), slots: slots, venue: venues(:phu_nhuan))
  end

  def at(hhmm)
    Time.zone.parse("2026-10-20 #{hhmm}")
  end
end
