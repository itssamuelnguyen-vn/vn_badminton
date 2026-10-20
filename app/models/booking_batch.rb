# Bookings a customer makes together, one per court (each court can have its own time range).
# They are created all-or-nothing: if one court cannot be booked, none is.
#
#   batch = BookingBatch.new(user: current_user, slots: [{ court_id: 1, starts_at: "...", ends_at: "..." }], note: "...",
#                            items: [{ product_id: 3, quantity: 2 }], voucher_code: "HE2026")
#   batch.hold     # => true when the slots are held for the customer for Booking::HOLD_DURATION (confirmation page)
#   batch.reserve  # => true when every booking was saved as confirmed
#   batch.reserve_for_payment   # => the Payment to transfer (court price less the best offer, plus extras)
#   batch.reserve_with_package(purchase) # => true when booked and paid with prepaid hours (PackagePurchase)
#
# A customer has at most one held selection: holding or confirming replaces the previous one, so confirming
# turns the held slots into bookings, and someone else's hold that expired no longer blocks anything.
#
# Besides each booking's own checks, the customer must not be locked out for cancelling too often,
# and may hold at most Venue#max_upcoming_bookings upcoming bookings.
class BookingBatch
  attr_reader :bookings, :errors, :venue

  def initialize(user:, slots:, note: nil, items: [], voucher_code: nil, venue: Venue.main)
    @user = user
    @venue = venue
    @errors = []
    @item_params = Array(items)
    @voucher_code = voucher_code.presence
    courts = venue.courts.active.where(id: slots.map { |slot| slot[:court_id] }).index_by(&:id)

    @bookings = slots.map do |slot|
      court = courts.fetch(slot[:court_id].to_i) { raise ActiveRecord::RecordNotFound, "Court #{slot[:court_id]} not found" }
      court.bookings.new(user: user, source: :online, starts_at: slot[:starts_at], ends_at: slot[:ends_at], note: note.presence)
    end.sort_by { |booking| [ booking.court.position, booking.court.id, booking.starts_at.to_i ] }
    attach_items
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
    held = save_bookings(hold_until: now + Booking::HOLD_DURATION)
    HoldExpiryJob.set(wait_until: held_until + 1.second).perform_later(bookings.map(&:court_id).uniq) if held
    held
  end

  def held_until
    bookings.map(&:expires_at).compact.min
  end

  # The confirmed choice of the customer, waiting for the transfer: the bookings stay held (pending) for
  # Payment::WINDOW (plus Payment::GRACE for slow bank notifications), linked to a Payment to transfer.
  # Returns the Payment, or nil when the bookings could not be saved (errors on the bookings).
  def reserve_for_payment(created_by: @user, now: Time.current)
    # A code that cannot be used stops the order, so the customer knows before paying (a code saving less than
    # the member tier does not: the tier applies).
    if @voucher_code && (problem = offer.voucher_problem) && problem != :tier_better
      @errors = [ offer.voucher_message ]
      return
    end
    deadline = now + Payment::WINDOW
    payment = nil
    Booking.transaction do
      save_bookings(hold_until: deadline + Payment::GRACE) || raise(ActiveRecord::Rollback)
      # Priced once saved; the best offer then taken off; one payment for all of them.
      offer = self.offer
      offer.spread(bookings)
      bookings.each { |booking| booking.update_columns(discount_vnd: booking.discount_vnd) }
      payment = Payment.create!(purpose: :bookings, user: @user, created_by: created_by, amount_vnd: total_amount_vnd, expires_at: deadline,
                                discount_vnd: offer.discount_vnd, offer: offer.kind)
      VoucherRedemption.create!(voucher: offer.voucher, user: @user, payment: payment, discount_vnd: offer.discount_vnd) if offer.voucher
      Booking.where(id: bookings.map(&:id)).update_all(payment_id: payment.id)
      bookings.each { |booking| booking.payment = payment }
    end
    return unless payment

    HoldExpiryJob.set(wait_until: payment.expires_at + Payment::GRACE + 1.second).perform_later(bookings.map(&:court_id).uniq)
    payment
  end

  # Booked and paid at once with prepaid hours: confirmed, taking their minutes off the package (locked, so two
  # bookings cannot spend the same minutes). Extras cannot be added (they are paid at the counter).
  def reserve_with_package(purchase, now: Time.current)
    return false if bookings.empty?
    if @item_params.any?
      @errors = [ I18n.t("booking_batch.errors.package_no_items") ]
      return false
    end

    Booking.transaction do
      purchase.lock!
      if (problem = purchase.problem(bookings, now))
        @errors = [ I18n.t("booking_batch.errors.package.#{problem}") ]
        raise ActiveRecord::Rollback
      end

      bookings.each do |booking|
        booking.assign_attributes(package_purchase: purchase, package_minutes: booking.duration_minutes, payment_status: :paid, paid_at: now)
      end
      save_bookings || raise(ActiveRecord::Rollback)
      # The whole court price is covered by the hours.
      bookings.each { |booking| booking.update_columns(discount_vnd: booking.total_amount_vnd) }
      purchase.update!(minutes_left: purchase.minutes_left - bookings.sum(&:duration_minutes))
    end
    bookings.all?(&:persisted?) && errors.empty?
  end

  # The best discount for this order (tier or voucher), from the prices the bookings have before saving.
  def offer
    bookings.each(&:quote_price) unless bookings.all?(&:persisted?)
    Pricing::Offer.best(user: @user, bookings: bookings, voucher_code: @voucher_code, venue: venue)
  end

  def errors?
    errors.any? || bookings.any? { |booking| booking.errors.any? }
  end

  def total_amount_vnd
    bookings.sum(&:charged_vnd)
  end

  def items_amount_vnd
    bookings.sum(&:items_amount_vnd)
  end

  private

  # The products go with the first booking (the staff hand them over at its check-in).
  def attach_items
    first = bookings.min_by(&:starts_at) or return
    products = venue.products.active.where(id: @item_params.map { |item| item[:product_id] }).index_by(&:id)
    @item_errors = []
    @item_params.group_by { |item| item[:product_id].to_i }.each do |product_id, picks|
      product = products[product_id]
      quantity = picks.sum { |item| item[:quantity].to_i }
      next @item_errors << I18n.t("booking_batch.errors.product_unavailable") unless product
      next @item_errors << I18n.t("booking_batch.errors.quantity_invalid", max: BookingItem::MAX_QUANTITY) unless quantity.between?(1, BookingItem::MAX_QUANTITY)

      first.items.build(product: product, name: product.name, unit_price_vnd: product.price_vnd, quantity: quantity)
    end
    first.items_amount_vnd = first.items.sum(&:amount_vnd)
  end

  def save_bookings(hold_until: nil)
    return false if bookings.empty?

    Booking.transaction(requires_new: true) do
      # Locking the customer's row makes two bookings sent at the same time wait for each other,
      # so they cannot both get past the upcoming-bookings limit.
      @user.lock!
      Booking.lock_courts!(bookings.map(&:court_id))
      Booking.delete_holds!(@user.bookings) # the customer's previous hold is replaced (or confirmed) by this one
      supersede_awaiting_payments
      Booking.release_expired_holds!(bookings.map(&:court_id))
      raise ActiveRecord::Rollback unless customer_allowed?

      bookings.each { |booking| booking.assign_attributes(status: :pending, expires_at: hold_until) } if hold_until
      results = bookings.map(&:reserve)
      raise ActiveRecord::Rollback unless results.all?
    end
    bookings.all?(&:persisted?)
  end

  # Paying again for the same slots (double click, back button) replaces the customer's earlier unpaid try.
  def supersede_awaiting_payments
    bookings.each do |booking|
      @user.bookings.pending.where.not(payment_id: nil).where(court_id: booking.court_id)
           .overlapping(booking.starts_at, booking.ends_at).includes(:user, :payment, court: :venue).each { |old| old.cancel!(by: @user, reason: "payment_replaced") }
    end
  end

  # The customer's unexpired hold, when it is for exactly the picked slots.
  def current_hold(now)
    held = @user.bookings.pending.where(expires_at: now..).includes(:court).to_a
    key = ->(b) { [ b.court_id, b.starts_at.to_i, b.ends_at.to_i ] }
    return if held.empty? || held.map(&key).sort != bookings.map(&key).sort

    held.sort_by { |booking| [ booking.court.position, booking.court.id, booking.starts_at.to_i ] }
  end

  def customer_allowed?(now = Time.current)
    @errors = @item_errors.to_a.dup
    if @errors.any?
      # A product that went away or a wrong quantity: nothing is booked.
    elsif CustomerProfile.blocked?(@user.phone)
      @errors << I18n.t("booking_batch.errors.blacklisted")
    elsif @user.booking_locked?(now)
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
