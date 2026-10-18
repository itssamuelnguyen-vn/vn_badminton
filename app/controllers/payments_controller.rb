# The payment page: the VietQR code and transfer details of a payment, opened by its unguessable token
# (also sent by staff to phone customers without an account). It refreshes itself once paid or expired.
class PaymentsController < ApplicationController
  def show
    @payment = Payment.find_by!(token: params[:token])
    @venue = Venue.main
    @bookings = @payment.bookings.includes(:court).order(:starts_at)
  end
end
