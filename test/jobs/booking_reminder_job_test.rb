require "test_helper"

class BookingReminderJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup { travel_to Time.zone.parse("2026-10-19 10:00") }

  test "reminds bookings starting within 3 hours, once" do
    due = book(:court_one, "18:00")
    later = book(:court_two, "18:30")

    travel_to Time.zone.parse("2026-10-20 15:05") do
      assert_enqueued_email_with BookingMailer, :reminder, params: { booking: due } do
        BookingReminderJob.perform_now
      end
      assert_equal Time.current, due.reload.reminder_sent_at
      assert_nil later.reload.reminder_sent_at

      assert_no_enqueued_emails { BookingReminderJob.perform_now }
    end
  end

  test "skips bookings that do not need a reminder" do
    book(:court_one, "18:00").cancel!(by: users(:an))
    book(:court_two, "18:00").check_in!
    courts(:court_one).bookings.create!(kind: :block, starts_at: at("17:00"), ends_at: at("18:00"))
    courts(:court_one).bookings.create!(source: :walk_in, customer_name: "Khách lẻ", customer_phone: "0912 345 678",
                                        starts_at: at("19:00"), ends_at: at("20:00"))
    travel_to(Time.zone.parse("2026-10-20 16:30")) { book(:court_two, "19:00") } # booked 2.5 hours ahead

    travel_to Time.zone.parse("2026-10-20 16:55") do
      assert_no_enqueued_emails { BookingReminderJob.perform_now }
    end
  end

  test "does not remind bookings that already started" do
    book(:court_one, "18:00")

    travel_to Time.zone.parse("2026-10-20 18:05") do
      assert_no_enqueued_emails { BookingReminderJob.perform_now }
    end
  end

  private

  def at(time)
    Time.zone.parse("2026-10-20 #{time}")
  end

  def book(court, from)
    courts(court).bookings.create!(user: users(:an), starts_at: at(from), ends_at: at(from) + 1.hour)
  end
end
