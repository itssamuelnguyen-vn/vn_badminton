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
      status: booking.status, payment_status: booking.payment_status, discount_vnd: booking.discount_vnd,
      paid_with_package: booking.package_purchase_id.present?,
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
      can_review: booking.reviewable?(now),
      review: (review(booking.review) if booking.review)
    }
  end

  def loyalty(user, venue)
    tier = Loyalty::Tier.for(user, venue: venue)
    { tier: tier.key, name: tier.name, percent: tier.percent, hours: tier.hours.round(1), enabled: venue.loyalty_enabled?,
      next: (tier.next && { tier: tier.next[:key], name: I18n.t("loyalty.tiers.#{tier.next[:key]}"), hours: tier.next[:hours] }),
      tiers: Loyalty::Tier.thresholds(venue).map { |key, (hours, percent)| { tier: key, name: I18n.t("loyalty.tiers.#{key}"), hours: hours, percent: percent } } }
  end

  def package(package)
    { id: package.id, name: package.display_name, minutes: package.minutes, price_vnd: package.price_vnd, valid_days: package.valid_days,
      start_minute: package.start_minute, end_minute: package.end_minute }
  end

  def package_purchase(purchase)
    { id: purchase.id, name: purchase.display_name, status: purchase.status, minutes_total: purchase.minutes_total,
      minutes_left: purchase.minutes_left, expires_at: purchase.expires_at&.iso8601, start_minute: purchase.start_minute,
      end_minute: purchase.end_minute, payment_token: (purchase.payment&.token if purchase.awaiting?) }
  end

  def play_session(session, mine = [], now: Time.current)
    { id: session.id, title: session.display_title, description: session.description, courts: session.courts.map(&:display_name),
      starts_at: session.starts_at.iso8601, ends_at: session.ends_at.iso8601, capacity: session.capacity, seats_left: session.seats_left(now),
      price_vnd: session.price_vnd, level: session.level, status: session.status, bookable: session.bookable?(now),
      my_tickets: mine.map { |ticket| ticket(ticket, now: now) } }
  end

  def ticket(ticket, now: Time.current)
    { id: ticket.id, quantity: ticket.quantity, amount_vnd: ticket.amount_vnd, status: ticket.status,
      can_cancel: ticket.cancellable_by_customer?(now), cancel_without_refund: ticket.confirmed?,
      payment_token: (ticket.payment&.token if ticket.pending? && ticket.payment&.open?(now)) }
  end

  # A tournament in the customer's list (GD-01): what they run, and whether they created it.
  def tournament(tournament, viewer: nil)
    { token: tournament.share_token, title: tournament.title, description: tournament.description, event: tournament.event_name,
      discipline: tournament.discipline, play_format: tournament.play_format, group_size: tournament.group_size,
      advance_per_group: tournament.advance_per_group, played_on: tournament.played_on&.iso8601, date: tournament.play_date&.iso8601,
      status: tournament.status, created_by: tournament.created_by.full_name, creator: tournament.creator?(viewer),
      # Paths on the website (the app adds its server address) to send to friends.
      share_path: Rails.application.routes.url_helpers.tournament_path(token: tournament.share_token) }
  end

  # The tournament's page in the app: players, courts, group tables, every match, and what the viewer may do
  # (the creator sets it up and sees the organizer link; organizers call matches and enter results).
  def tournament_details(tournament, viewer: nil, now: Time.current)
    creator = tournament.creator?(viewer)
    organizer = tournament.organizer?(viewer)
    side = ->(entry) { entry && { id: entry.id, name: entry.display_name } }
    standings = tournament.knockout? ? {} : Tournaments::Standings.new(tournament).groups
    matches = tournament.matches.ordered.includes(:court, :entry_a, :entry_b)
    bookings = tournament.bookings.where.not(status: :cancelled).includes(:court).order(:starts_at)
    tournament(tournament, viewer: viewer).merge(
      organizer: organizer, champion: tournament.champion&.display_name, redrawable: creator && tournament.redrawable?,
      entries: tournament.entries.map { |entry| { id: entry.id, name: entry.name, partner_name: entry.partner_name, seed: entry.seed } },
      bookings: bookings.map { |booking| { id: booking.id, court: booking.court.display_name, starts_at: booking.starts_at.iso8601, ends_at: booking.ends_at.iso8601 } },
      courts: organizer ? tournament.courts.map { |court| { id: court.id, name: court.display_name } } : [],
      linkable_bookings: creator ? tournament.linkable_bookings(viewer, now).map { |booking| tournament_booking(booking, tournament) } : [],
      organizer_path: (Rails.application.routes.url_helpers.organize_tournament_path(token: tournament.share_token, organizer_token: tournament.organizer_token) if creator),
      organizers: creator ? tournament.organizers.includes(:user).order(:created_at).map { |organizer| { user_id: organizer.user_id, name: organizer.user.full_name } } : [],
      groups: standings.map do |number, rows|
        { number: number, rows: rows.map do |row|
          { entry: side.(row.entry), played: row.played, won: row.won, lost: row.lost, games_for: row.games_for,
            games_against: row.games_against, point_difference: row.point_difference }
        end }
      end,
      matches: matches.map do |match|
        { id: match.id, stage: match.stage, group: match.group_number, round: match.round, round_name: match.round_name, position: match.position,
          a: side.(match.entry_a), b: side.(match.entry_b), winner_id: match.winner_id, scores: match.scores, walkover: match.walkover,
          bye: match.bye?, court: match.court&.display_name, court_id: match.court_id, called_at: match.called_at&.iso8601,
          editable: organizer && match.editable?, ready: match.ready? }
      end
    )
  end

  def tournament_booking(booking, tournament)
    { id: booking.id, court: booking.court.display_name, starts_at: booking.starts_at.iso8601, ends_at: booking.ends_at.iso8601,
      linked: booking.tournament_id == tournament.id }
  end

  # Upcoming shared bookings only; members are shown by name.
  def group(group, viewer, now: Time.current)
    { id: group.id, name: group.name, invite_code: group.invite_code, owner: group.owner_id == viewer.id,
      members: group.members.sort_by(&:full_name).map { |member| { id: member.id, name: member.full_name, owner: member.id == group.owner_id } },
      shares: group.upcoming_shares(now).map do |share|
        booking = share.booking
        { id: share.id, shared_by: share.shared_by.full_name, mine: share.shared_by_id == viewer.id, players: share.players,
          per_player_vnd: share.per_player_vnd, total_vnd: booking.charged_vnd, court: booking.court.display_name,
          starts_at: booking.starts_at.iso8601, ends_at: booking.ends_at.iso8601, code: booking.code }
      end }
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
      months: series.billed_months(today).map do |month|
        bill = series.billing(month)
        { month: month.strftime("%Y-%m"), sessions: bill.billable.count, amount_vnd: bill.amount_vnd, credit_vnd: bill.credit_vnd,
          due_vnd: bill.due_vnd, paid: bill.paid?, payment_token: awaiting[month]&.token }
      end
    }
  end

  def payment(payment, venue, now: Time.current)
    received = payment.received_vnd
    {
      token: payment.token, code: payment.code, status: payment.status, open: payment.open?(now), can_cancel: payment.cancellable_by?(payment.user, now),
      amount_vnd: payment.amount_vnd, discount_vnd: payment.discount_vnd, offer: payment.offer, purpose: payment.purpose,
      received_vnd: received, remaining_vnd: [ payment.amount_vnd - received, 0 ].max,
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
