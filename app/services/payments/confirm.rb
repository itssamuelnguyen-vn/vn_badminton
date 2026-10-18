module Payments
  # Records an awaiting payment as paid (by a matching transfer, or by hand by the owner/staff) and does what
  # it pays for: confirms the held bookings, or marks a series month paid. Emails the booking confirmation.
  module Confirm
    def self.call(payment, by: nil, transaction: nil, now: Time.current)
      Payment.transaction do
        payment.lock!
        raise ArgumentError, "Payment is not awaiting" unless payment.awaiting?

        payment.update!(status: :paid, paid_at: now, bank_transaction: transaction)
        if payment.for_bookings?
          payment.bookings.pending.each do |booking|
            booking.update!(status: :confirmed, expires_at: nil, payment_status: :paid, paid_at: now)
          end
        else
          payment.series.billing(payment.series_month).mark_paid!(by: by || payment.created_by, now: now)
        end
      end
      confirmed = payment.bookings.confirmed.to_a
      if payment.for_bookings? && confirmed.any? && confirmed.first.user
        BookingMailer.with(bookings: confirmed, locale: payment.user&.locale).confirmed.deliver_later
      end
      payment
    end
  end
end
