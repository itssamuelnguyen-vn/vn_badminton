# The JSON shapes of the mobile app's API (Api::V1). Times are ISO 8601 with the venue's offset, amounts in VND.
module ApiJson
  module_function

  def user(user)
    {
      id: user.id, full_name: user.full_name, email: user.email, phone: user.phone, locale: user.locale,
      email_verified: user.confirmed?, booking_locked_until: user.booking_locked_until&.iso8601
    }
  end

  def venue(venue)
    {
      name: venue.name, address: venue.address, phone: venue.phone, contact_links: venue.contact_links,
      payments_enabled: venue.payments_enabled?,
      courts: venue.courts.active.map { |court| { id: court.id, name: court.display_name } },
      policy: {
        min_booking_minutes: venue.min_booking_minutes, max_booking_minutes: venue.max_booking_minutes,
        booking_horizon_days: venue.booking_horizon_days, cancellation_cutoff_hours: venue.cancellation_cutoff_hours,
        max_upcoming_bookings: venue.max_upcoming_bookings, slot_minutes: 30
      },
      prices: venue.price_rules.active.where(court_id: nil).order(:priority, :start_minute).map do |rule|
        { name: rule.display_name, days_of_week: rule.days_of_week, start_minute: rule.start_minute, end_minute: rule.end_minute,
          price_per_hour_vnd: rule.price_per_hour_vnd }
      end
    }
  end

  def booking(booking, now: Time.current)
    {
      code: booking.code, court: { id: booking.court_id, name: booking.court.display_name },
      starts_at: booking.starts_at.iso8601, ends_at: booking.ends_at.iso8601,
      status: booking.status, payment_status: booking.payment_status, amount_vnd: booking.total_amount_vnd,
      note: booking.note, held_until: (booking.expires_at&.iso8601 if booking.pending?),
      cancellation_reason: booking.cancellation_reason, refund_vnd: booking.refund_vnd,
      series: booking.series_id.present?,
      # A series session is "skipped" rather than cancelled, with the same rule.
      can_cancel: booking.cancellable_by_customer?(now),
      # Cancelling a paid booking gives no refund (only a venue fault does).
      cancel_without_refund: booking.payment_paid?,
      payment_token: (booking.payment&.token if booking.pending?)
    }
  end

  def payment(payment, venue, now: Time.current)
    received = payment.received_vnd
    {
      token: payment.token, code: payment.code, status: payment.status, open: payment.open?(now),
      amount_vnd: payment.amount_vnd, received_vnd: received, remaining_vnd: [ payment.amount_vnd - received, 0 ].max,
      expires_at: payment.expires_at&.iso8601, paid_at: payment.paid_at&.iso8601,
      bank: { code: venue.bank_code, account_number: venue.bank_account_number, account_name: venue.bank_account_name },
      qr_image_url: payment.qr_url(venue),
      bookings: payment.bookings.includes(:court).order(:starts_at).map { |booking| booking(booking, now: now) }
    }
  end

  def errors(batch)
    (batch.errors + batch.bookings.flat_map { |booking| booking.errors.full_messages }).uniq
  end
end
