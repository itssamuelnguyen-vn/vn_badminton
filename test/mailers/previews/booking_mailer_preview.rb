# Preview the booking emails at http://localhost:3000/rails/mailers/booking_mailer
# (uses the latest booking of a customer in the development database, in that customer's language).
class BookingMailerPreview < ActionMailer::Preview
  def confirmed
    BookingMailer.with(bookings: [ booking ]).confirmed
  end

  def cancelled_by_customer
    BookingMailer.with(booking: cancelled(by: booking.user)).cancelled
  end

  def cancelled_by_venue
    BookingMailer.with(booking: cancelled(by: User.admin.first)).cancelled
  end

  def reminder
    BookingMailer.with(booking: booking).reminder
  end

  private

  def booking
    @booking ||= Booking.kind_reservation.joins(:user).merge(User.customer).order(:id).last ||
                 raise("Run bin/rails db:seed to create demo bookings first")
  end

  # Not saved: only how the email looks matters here.
  def cancelled(by:)
    booking.tap { |b| b.assign_attributes(status: :cancelled, cancelled_at: Time.current, cancelled_by: by) }
  end
end
