require "test_helper"

# Real concurrent requests: each thread uses its own database connection, so the usual per-test
# transaction (which would put both threads on one connection) is turned off and rows are cleaned up.
class BookingConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @slot = { court_id: courts(:court_one).id, starts_at: Time.zone.parse("2026-10-20 18:00"), ends_at: Time.zone.parse("2026-10-20 19:00") }
  end

  teardown { Booking.delete_all }

  test "two customers booking the same slot at once: one gets it, the other a friendly error" do
    5.times do
      results = race(users(:an), users(:chi)) { |user| BookingBatch.new(user: user, slots: [ @slot ]).then { |batch| [ batch.reserve, batch ] } }

      assert_equal [ false, true ], results.map(&:first).sort_by { |ok| ok ? 1 : 0 }
      loser = results.find { |ok, _| !ok }.last
      assert loser.bookings.first.errors.of_kind?(:base, :slot_taken) || loser.bookings.first.errors.of_kind?(:base, :slot_just_taken)
      assert_equal 1, Booking.holding_slot.count
      Booking.delete_all
    end
  end

  test "a booking waits for another one on the same court, then sees it" do
    holding = Queue.new
    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Booking.transaction do
          Booking.lock_courts!([ @slot[:court_id] ])
          courts(:court_one).bookings.create!(user: users(:an), starts_at: @slot[:starts_at], ends_at: @slot[:ends_at])
          holding << :saved_but_not_committed
          sleep 0.5
        end
      end
    end
    holding.pop

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    second = courts(:court_one).bookings.new(user: users(:chi), starts_at: @slot[:starts_at], ends_at: @slot[:ends_at])
    assert_not second.reserve
    waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    first.join

    assert_operator waited, :>=, 0.3, "the second booking should wait for the first transaction"
    assert second.errors.of_kind?(:base, :slot_taken), "after waiting it should see the first booking (#{second.errors.details})"
  end

  test "the database still refuses the second booking when both passed the soft check" do
    results = race(users(:an), users(:chi)) do |user|
      booking = courts(:court_one).bookings.new(user: user, starts_at: @slot[:starts_at], ends_at: @slot[:ends_at])
      booking.define_singleton_method(:slot_free) { } # as if both had checked before either saved
      [ booking.reserve, booking ]
    end

    assert_equal 1, results.count(&:first)
    assert results.find { |ok, _| !ok }.last.errors.of_kind?(:base, :slot_just_taken)
    assert_equal 1, Booking.holding_slot.count
  end

  private

  # Runs the block for each user in its own thread, releasing them together. Exceptions are re-raised.
  def race(*users, &block)
    gate = Queue.new
    threads = users.map do |user|
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection { block.call(user) }
      end
    end
    users.size.times { gate << :go }
    threads.map(&:value)
  end
end
