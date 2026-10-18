# Emails a reminder to customers whose booking starts within the next 3 hours.
# Runs every 10 minutes (config/recurring.yml); each booking is reminded once.
class BookingReminderJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Booking.due_for_reminder(now).find_each do |booking|
      # Claim the booking first, so two overlapping runs never send the same reminder twice.
      claimed = Booking.where(id: booking.id, reminder_sent_at: nil).update_all(reminder_sent_at: now)
      BookingMailer.with(booking: booking).reminder.deliver_later if claimed == 1
    end
  end
end
