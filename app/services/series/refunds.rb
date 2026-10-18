module Series
  # Decides, once a cancelled series session is over, what the regular customer gets back:
  # - nothing if its month was not paid (the session was simply not billed);
  # - the full price if the venue cancelled it (BookingSeries::VENUE_CLOSED);
  # - if the customer skipped it (BookingSeries::SKIPPED): the share of its time someone else booked and played
  #   (bookings not cancelled and not no-shows), so the venue keeps the money when nobody took the slot.
  # The amount is stored in series_refund_vnd and taken off the next unpaid month (Series::Billing).
  module Refunds
    REFUNDABLE_REASONS = [ BookingSeries::SKIPPED, BookingSeries::VENUE_CLOSED ].freeze
    PLAYED_STATUSES = %w[confirmed checked_in completed].freeze

    def self.settle_due(now = Time.current)
      Booking.cancelled.where.not(series_id: nil).where(series_refund_vnd: nil).where(ends_at: ..now)
             .includes(:series).find_each { |booking| settle(booking) }
    end

    def self.settle(booking)
      amount = refund_for(booking)
      attributes = { series_refund_vnd: amount }
      attributes[:payment_status] = :refunded if amount.positive? && booking.payment_paid?
      booking.update_columns(attributes)
      amount
    end

    def self.refund_for(booking)
      return 0 unless REFUNDABLE_REASONS.include?(booking.cancellation_reason)
      return 0 unless booking.series.billing(booking.starts_at.in_time_zone(booking.series.venue.zone).to_date).paid?
      return booking.total_amount_vnd if booking.cancellation_reason == BookingSeries::VENUE_CLOSED

      played = Booking.kind_reservation.where(court_id: booking.court_id, status: PLAYED_STATUSES)
                      .where.not(id: booking.id).overlapping(booking.starts_at, booking.ends_at)
      minutes = played.sum { |other| ([ other.ends_at, booking.ends_at ].min - [ other.starts_at, booking.starts_at ].max) / 60 }
      (booking.total_amount_vnd * minutes / booking.duration_minutes).round
    end
  end
end
