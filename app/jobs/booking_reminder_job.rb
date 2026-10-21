# Emails a reminder (and a push notification to the app, Push) to customers whose booking starts within the next 3 hours.
# Runs every 10 minutes (config/recurring.yml); each booking is reminded once.
class BookingReminderJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Booking.due_for_reminder(now).find_each do |booking|
      # Claim the booking first, so two overlapping runs never send the same reminder twice.
      claimed = Booking.where(id: booking.id, reminder_sent_at: nil).update_all(reminder_sent_at: now)
      next unless claimed == 1

      BookingMailer.with(booking: booking).reminder.deliver_later
      Push.booking_reminder(booking)
    end
  end
end
