# The JSON shapes of the mobile app's API (Api::V1). Times are ISO 8601 with the venue's offset, amounts in VND.
module ApiJson
  module_function

  def user(user)
    {
      id: user.id, full_name: user.full_name, email: user.email, phone: user.phone, locale: user.locale,
      email_verified: user.confirmed?, booking_locked_until: user.booking_locked_until&.iso8601,
      birth_year: user.birth_year, gender: user.gender, skill_level: user.skill_level,
      # Relative to the server (a signed link that redirects to the file); null without a photo.
      avatar_path: (Rails.application.routes.url_helpers.rails_blob_path(user.avatar, only_path: true) if user.avatar.attached?)
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
      products: venue.products.active.ordered.map { |product| product(product) },
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
      status: booking.status, payment_status: booking.payment_status,
      # The court's price; total_vnd adds the products picked with it (items).
      amount_vnd: booking.total_amount_vnd, items_amount_vnd: booking.items_amount_vnd, total_vnd: booking.charged_vnd,
      items: booking.items.map { |item| { name: item.display_name, quantity: item.quantity, unit_price_vnd: item.unit_price_vnd } },
      note: booking.note, held_until: (booking.expires_at&.iso8601 if booking.pending?),
      cancellation_reason: booking.cancellation_reason, refund_vnd: booking.refund_vnd,
      series: booking.series_id.present?,
      # A series session is "skipped" rather than cancelled, with the same rule.
      can_cancel: booking.cancellable_by_customer?(now),
      # Moved on the schedule in reschedule mode (GET /schedule?reschedule=CODE); not for series sessions.
      can_reschedule: booking.persisted? && booking.reschedulable_by_customer?(now),
      # Cancelling a paid booking gives no refund (only a venue fault does).
      cancel_without_refund: booking.payment_paid?,
      payment_token: (booking.payment&.token if booking.pending?),
      can_review: booking.persisted? && booking.user && booking.review.nil? && Review.allowed?(booking, booking.user, now),
      review: (review(booking.review) if booking.review)
    }
  end

  def product(product)
    { id: product.id, name: product.display_name, price_vnd: product.price_vnd }
  end

  def review(review)
    { rating: review.rating, comment: review.comment, created_at: review.created_at.iso8601 }
  end

  def announcement(announcement)
    { id: announcement.id, title: announcement.display_title, body: announcement.display_body, tone: announcement.tone,
      starts_on: announcement.starts_on.iso8601, ends_on: announcement.ends_on.iso8601 }
  end

  def waitlist_entry(entry)
    { id: entry.id, starts_at: entry.starts_at.iso8601, ends_at: entry.ends_at.iso8601, notified_at: entry.notified_at&.iso8601 }
  end

  def series_request(request)
    { id: request.id, court_ids: request.court_ids, courts: request.courts.map(&:display_name), days_of_week: request.days_of_week,
      start_minute: request.start_minute, end_minute: request.end_minute, starts_on: request.starts_on.iso8601,
      ends_on: request.ends_on.iso8601, note: request.note, status: request.status, decline_reason: request.decline_reason,
      series_id: request.series_id, created_at: request.created_at.iso8601 }
  end

  # A regular customer's weekly booking, with each month's bill and the transfer waiting for it (if any).
  def series(series, venue, today: venue.today)
    awaiting = series.payments.awaiting.index_by(&:series_month)
    {
      id: series.id, courts: series.courts.map(&:display_name), days_of_week: series.days_of_week,
      start_minute: series.start_minute, end_minute: series.end_minute, starts_on: series.starts_on.iso8601,
      ends_on: series.ends_on.iso8601, price_per_hour_vnd: series.price_per_hour_vnd,
      months: series.months.select { |month| month >= today.beginning_of_month.prev_month }.map do |month|
        bill = series.billing(month)
        { month: month.strftime("%Y-%m"), sessions: bill.billable.count, amount_vnd: bill.amount_vnd, credit_vnd: bill.credit_vnd,
          due_vnd: bill.due_vnd, paid: bill.paid?, payment_token: awaiting[month]&.token }
      end
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
