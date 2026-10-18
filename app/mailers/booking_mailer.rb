class BookingMailer < ApplicationMailer
  helper :bookings

  # Nothing goes to a deleted account (Accounts::Deletion): its address is no longer the customer's.
  after_action { message.perform_deliveries = false if [ @booking, *@bookings ].compact.first&.user&.deleted_at }

  # One email for the bookings made together (one per court):
  #   BookingMailer.with(bookings:, locale: I18n.locale).confirmed.deliver_later
  # The locale is passed in because the email is rendered later by a background job.
  # Without it (bookings made by the owner), the customer's own language is used.
  def confirmed
    @bookings = params[:bookings]
    user = @bookings.first.user

    I18n.with_locale(params[:locale] || user.locale) do
      mail to: user.email, subject: t(".subject", codes: @bookings.map(&:code).join(", "))
    end
  end

  # Sent when a booking is cancelled, by the customer or by the owner:
  #   BookingMailer.with(booking:).cancelled.deliver_later
  def cancelled
    @booking = params[:booking]
    @by_customer = @booking.cancelled_by == @booking.user

    I18n.with_locale(@booking.user.locale) do
      mail to: @booking.user.email, subject: t(".subject", code: @booking.code)
    end
  end

  # Sent when a booking moves (by the customer or the venue):
  #   BookingMailer.with(booking:, previous: { "court_id" => .., "starts_at" => .., "ends_at" => .. }).rescheduled.deliver_later
  def rescheduled
    @booking = params[:booking]
    @previous_court = Court.find(params[:previous]["court_id"])
    @previous_starts_at = params[:previous]["starts_at"]
    @previous_ends_at = params[:previous]["ends_at"]

    I18n.with_locale(@booking.user.locale) do
      mail to: @booking.user.email, subject: t(".subject", code: @booking.code)
    end
  end

  # Sent by BookingReminderJob a few hours before the booking starts.
  def reminder
    @booking = params[:booking]

    I18n.with_locale(@booking.user.locale) do
      mail to: @booking.user.email, subject: t(".subject", court: @booking.court.display_name,
                                                          time: l(@booking.starts_at, format: :slot))
    end
  end
end
