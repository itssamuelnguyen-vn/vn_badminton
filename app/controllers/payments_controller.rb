# The payment page: the VietQR code and transfer details of a payment, opened by its unguessable token
# (also sent by staff to phone customers without an account). It refreshes itself once paid or expired.
class PaymentsController < ApplicationController
  def show
    @payment = Payment.find_by!(token: params[:token])
    @venue = Venue.main
    @bookings = @payment.bookings.includes(:court).order(:starts_at)
  end

  # The customer gives up before transferring (Payment#cancel_by!): back to the schedule of that day to pick
  # another time, or to the open play list.
  def cancel
    payment = Payment.find_by!(token: params[:token])
    payment.cancel_by!(current_user)
    day = payment.bookings.minimum(:starts_at)&.in_time_zone(Venue.main.zone)&.to_date
    redirect_to (payment.for_tickets? ? play_sessions_path : root_path(date: day)), notice: t(".success")
  rescue ArgumentError
    redirect_to payment_path(payment), alert: t(".not_allowed")
  end

  # The QR image as a file, for the "save the QR" button (Payments::QrImage). Only while the payment is open.
  def qr
    payment = Payment.find_by!(token: params[:token])
    return head :not_found unless payment.open?

    send_data Payments::QrImage.fetch(payment.qr_url(Venue.main)), type: "image/png", filename: "QR-#{payment.code}.png"
  rescue Payments::QrImage::Error
    head :bad_gateway
  end
end
