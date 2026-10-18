module Payments
  # Records a payment as paid (by its transfers, or by hand by the owner/staff) and does what it pays for:
  # confirms the held bookings, or marks a series month paid. Emails the booking confirmation.
  # Paid after its deadline, the bookings are taken back only if their courts are still free and they have not
  # started; otherwise nothing changes and it returns false (the money is to be refunded).
  module Confirm
    def self.call(payment, by: nil, transaction: nil, now: Time.current)
      bookings = Payment.transaction(requires_new: true) do
        payment.lock!
        raise ArgumentError, "Payment is not payable" unless payment.awaiting? || payment.expired?

        bookings = payment.for_bookings? ? payable_bookings(payment, now) : []
        raise ActiveRecord::Rollback unless bookings

        payment.update!(status: :paid, paid_at: now, bank_transaction: transaction)
        bookings.each do |booking|
          booking.update!(status: :confirmed, expires_at: nil, cancelled_at: nil, cancellation_reason: nil,
                          payment_status: :paid, paid_at: now)
        end
        payment.series.billing(payment.series_month).mark_paid!(by: by || payment.created_by, now: now) if payment.for_series_period?
        bookings
      end
      return false unless bookings

      if bookings.any? && bookings.first.user
        BookingMailer.with(bookings: bookings, locale: payment.user&.locale).confirmed.deliver_later
      end
      payment
    rescue ActiveRecord::ExclusionViolation
      false
    end

    # In time, the bookings still hold their courts. Late, they may have been released (cancelled as
    # PAYMENT_EXPIRED) and are checked again with the courts locked; nil when one cannot be taken back.
    def self.payable_bookings(payment, now)
      return payment.bookings.pending.to_a if payment.open?(now)

      bookings = payment.bookings.where(status: :pending).or(payment.bookings.where(cancellation_reason: Booking::PAYMENT_EXPIRED)).to_a
      court_ids = bookings.map(&:court_id)
      Booking.lock_courts!(court_ids)
      Booking.release_expired_holds!(court_ids, now: now)
      bookings.each(&:reload)
      bookings if bookings.all? { |booking| booking.starts_at > now && !taken?(booking, now) }
    end

    def self.taken?(booking, now)
      Booking.holding_slot(now).where(court_id: booking.court_id).where.not(id: booking.id).overlapping(booking.starts_at, booking.ends_at).exists?
    end
  end
end
