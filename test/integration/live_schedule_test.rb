require "test_helper"

# Open schedules of a date refresh in place when bookings on that date change (Schedule::Live).
class LiveScheduleTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @stream = Schedule::Live.stream(venues(:phu_nhuan), Date.new(2026, 10, 20))
    @slots = { "0" => { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:00").iso8601 } }
  end

  test "the customer schedule and the owner's board subscribe to the date and refresh by morphing" do
    get root_path(date: "2026-10-20")
    assert_select "turbo-cable-stream-source[signed-stream-name='#{Turbo::StreamsChannel.signed_stream_name(@stream)}']"
    assert_select "meta[name=turbo-refresh-method][content=morph]", visible: false
    assert_select "meta[name=turbo-refresh-scroll][content=preserve]", visible: false
    assert_select "input#multiple-courts[data-turbo-permanent]"

    sign_in users(:owner)
    get admin_root_path(date: "2026-10-20")
    assert_select "turbo-cable-stream-source[signed-stream-name='#{Turbo::StreamsChannel.signed_stream_name(@stream)}']"
  end

  test "holding, releasing and confirming refresh the schedules of that date" do
    sign_in users(:an)

    assert_equal 1, refreshes { get new_booking_path(slots: @slots) }, "hold"
    assert_equal 1, refreshes { delete release_hold_bookings_path(date: "2026-10-20") }, "release"
    get new_booking_path(slots: @slots)
    assert_operator refreshes { post bookings_path, params: { booking: { slots: @slots } } }, :>=, 1, "confirm"
    assert_equal 0, refreshes(Schedule::Live.stream(venues(:phu_nhuan), Date.new(2026, 10, 21))) { get new_booking_path(slots: @slots) },
                 "other dates are left alone"
  end

  test "a failed booking refreshes nothing" do
    courts(:court_one).bookings.create!(user: users(:chi), starts_at: at("18:00"), ends_at: at("19:00"))
    sign_in users(:an)

    assert_equal 0, refreshes { post bookings_path, params: { booking: { slots: @slots } } }
  end

  test "the owner's actions refresh the schedule too" do
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))
    sign_in users(:owner)

    assert_equal 1, refreshes { patch cancel_admin_booking_path(booking) }
  end

  test "an expiring hold frees the slots for everyone without a reload" do
    sign_in users(:an)
    get new_booking_path(slots: @slots)
    job = enqueued_jobs.find { |j| j["job_class"] == "HoldExpiryJob" }
    assert job, "expiry is scheduled"
    assert_in_delta (3.minutes + 1.second).from_now.to_f, job["scheduled_at"].to_time.to_f, 1

    travel 3.minutes + 1.second
    assert_equal 1, refreshes { perform_enqueued_jobs(only: HoldExpiryJob) }
    assert_empty Booking.pending
  end

  private

  def at(time)
    Time.zone.parse("2026-10-20 #{time}")
  end

  # Number of refresh broadcasts the block sends on the stream.
  def refreshes(stream = @stream, &block)
    # Only refreshes queued by the block count; other queued jobs (e.g. a scheduled HoldExpiryJob) stay.
    enqueued_jobs.reject! { |job| job["job_class"] == "Turbo::Streams::BroadcastStreamJob" }
    capture_turbo_stream_broadcasts(stream) { block.call; perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) }
      .count { |broadcast| broadcast["action"] == "refresh" }
  end
end
