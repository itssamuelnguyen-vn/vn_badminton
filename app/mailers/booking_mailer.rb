class BookingMailer < ApplicationMailer
  helper :bookings

  # BookingMailer.with(booking:, locale: I18n.locale).confirmed.deliver_later
  # The locale is passed in because the email is rendered later by a background job.
  def confirmed
    @booking = params[:booking]

    I18n.with_locale(params[:locale] || I18n.default_locale) do
      mail to: @booking.user.email, subject: t(".subject", code: @booking.code)
    end
  end
end
