class BookingMailer < ApplicationMailer
  helper :bookings

  # One email for the bookings made together (one per court):
  #   BookingMailer.with(bookings:, locale: I18n.locale).confirmed.deliver_later
  # The locale is passed in because the email is rendered later by a background job.
  def confirmed
    @bookings = params[:bookings]

    I18n.with_locale(params[:locale] || I18n.default_locale) do
      mail to: @bookings.first.user.email, subject: t(".subject", codes: @bookings.map(&:code).join(", "))
    end
  end
end
