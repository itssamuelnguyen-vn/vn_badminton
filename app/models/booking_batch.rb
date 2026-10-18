# Bookings a customer makes together, one per court (each court can have its own time range).
# They are created all-or-nothing: if one court cannot be booked, none is.
#
#   batch = BookingBatch.new(user: current_user, slots: [{ court_id: 1, starts_at: "...", ends_at: "..." }], note: "...")
#   batch.hold     # => true when the slots are held for the customer for Booking::HOLD_DURATION (confirmation page)
#   batch.reserve  # => true when every booking was saved as confirmed
#
# A customer has at most one held selection: holding or confirming replaces the previous one, so confirming
# turns the held slots into bookings, and someone else's hold that expired no longer blocks anything.
#
# Besides each booking's own checks, the customer must not be locked out for cancelling too often,
# and may hold at most Venue#max_upcoming_bookings upcoming bookings.
class BookingBatch
  attr_reader :bookings, :errors, :venue

  def initialize(user:, slots:, note: nil, venue: Venue.main)
    @user = user
    @venue = venue
    @errors = []
    courts = venue.courts.active.where(id: slots.map { |slot| slot[:court_id] }).index_by(&:id)

    @bookings = slots.map do |slot|
      court = courts.fetch(slot[:court_id].to_i) { raise ActiveRecord::RecordNotFound, "Court #{slot[:court_id]} not found" }
      court.bookings.new(user: user, source: :online, starts_at: slot[:starts_at], ends_at: slot[:ends_at], note: note.presence)
    end.sort_by { |booking| [ booking.court.position, booking.court.id, booking.starts_at.to_i ] }
  end

  # Validates every booking (not just up to the first failure) so all problems can be shown.
  def valid?
    [ customer_allowed?, *bookings.map(&:validate) ].all?
  end

  def reserve
    save_bookings
  end

  # Opening the confirmation page again (reload, back button) keeps the same hold and expiry instead of
  # extending it, so a slot cannot be held forever by reloading.
  def hold(now = Time.current)
    return false if bookings.empty?

    if (current = current_hold(now))
      @bookings = current
      return true
    end
    save_bookings(hold_until: now + Booking::HOLD_DURATION)
  end

  def held_until
    bookings.map(&:expires_at).compact.min
  end

  def errors?
    errors.any? || bookings.any? { |booking| booking.errors.any? }
  end

  def total_amount_vnd
    bookings.sum(&:total_amount_vnd)
  end

  private

  def save_bookings(hold_until: nil)
    return false if bookings.empty?

    Booking.transaction do
      # Locking the customer's row makes two bookings sent at the same time wait for each other,
      # so they cannot both get past the upcoming-bookings limit.
      @user.lock!
      Booking.lock_courts!(bookings.map(&:court_id))
      @user.bookings.pending.delete_all # the customer's previous hold is replaced (or confirmed) by this one
      Booking.release_expired_holds!(bookings.map(&:court_id))
      raise ActiveRecord::Rollback unless customer_allowed?

      bookings.each { |booking| booking.assign_attributes(status: :pending, expires_at: hold_until) } if hold_until
      results = bookings.map(&:reserve)
      raise ActiveRecord::Rollback unless results.all?
    end
    bookings.all?(&:persisted?)
  end

  # The customer's unexpired hold, when it is for exactly the picked slots.
  def current_hold(now)
    held = @user.bookings.pending.where(expires_at: now..).includes(:court).to_a
    key = ->(b) { [ b.court_id, b.starts_at.to_i, b.ends_at.to_i ] }
    return if held.empty? || held.map(&key).sort != bookings.map(&key).sort

    held.sort_by { |booking| [ booking.court.position, booking.court.id, booking.starts_at.to_i ] }
  end

  def customer_allowed?(now = Time.current)
    @errors = []
    if @user.booking_locked?(now)
      @errors << I18n.t("booking_batch.errors.locked", until: I18n.l(@user.booking_locked_until.in_time_zone(venue.zone), format: :slot))
    else
      limit = venue.max_upcoming_bookings
      remaining = limit - @user.upcoming_bookings(now).count
      if remaining <= 0
        @errors << I18n.t("booking_batch.errors.limit_reached", count: limit)
      elsif bookings.size > remaining
        @errors << I18n.t("booking_batch.errors.too_many", count: limit, remaining: remaining)
      end
    end
    @errors.empty?
  end
end
