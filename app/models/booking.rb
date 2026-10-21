class Booking < ApplicationRecord
  SLOT_SECONDS = 30 * 60
  # Must match the WHERE clause of the "bookings_no_overlap" exclusion constraint.
  ACTIVE_STATUSES = %w[pending confirmed checked_in completed no_show].freeze
  CUSTOMER_CANCELLABLE_STATUSES = %w[pending confirmed].freeze
  REMINDER_LEAD_TIME = 3.hours
  # How long the confirmation page keeps the picked slots for the customer (status "pending").
  HOLD_DURATION = 3.minutes
  CODE_CHARS = [ *"A".."Z", *"0".."9" ] - %w[O 0 I 1] # drop characters that are easy to confuse over the phone
  # First key of the Postgres advisory locks taken per court (the second key is the court id).
  COURT_LOCK_NAMESPACE = 1_001

  enum :kind, { reservation: "reservation", block: "block" }, prefix: true, default: :reservation, validate: true
  enum :status, {
    pending: "pending", confirmed: "confirmed", checked_in: "checked_in",
    completed: "completed", cancelled: "cancelled", no_show: "no_show"
  }, default: :confirmed, validate: true
  enum :source, { online: "online", phone: "phone", walk_in: "walk_in", staff: "staff" },
       prefix: true, default: :online, validate: true
  enum :payment_status, { unpaid: "unpaid", paid: "paid", refunded: "refunded" },
       prefix: :payment, default: :unpaid, validate: true

  belongs_to :court
  belongs_to :user, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  belongs_to :series, class_name: "BookingSeries", optional: true, inverse_of: :bookings
  belongs_to :series_refund_period, class_name: "BookingSeriesPeriod", optional: true
  belongs_to :payment, optional: true
  belongs_to :refunded_by, class_name: "User", optional: true
  # Paid with prepaid hours (PackagePurchase): package_minutes were taken off it.
  belongs_to :package_purchase, optional: true
  # A block keeping a court for an open play session.
  belongs_to :play_session, optional: true

  # Why a booking was cancelled, besides a plain cancellation (see also BookingSeries reasons).
  PAYMENT_EXPIRED = "payment_expired" # the transfer did not arrive in time
  VENUE_FAULT = "venue_fault"         # the venue could not provide the court (outage, broken court): refunded
  has_one :venue, through: :court
  # Products picked with the booking (racket, shuttlecocks...), paid with it; their sum is items_amount_vnd.
  has_many :items, -> { order(:id) }, class_name: "BookingItem", inverse_of: :booking, dependent: :delete_all
  has_one :review, dependent: :destroy

  # Expired holds no longer count, even before they are deleted (see release_expired_holds!).
  scope :holding_slot, ->(now = Time.current) {
    where(status: ACTIVE_STATUSES).where("bookings.status <> 'pending' OR bookings.expires_at > ?", now)
  }
  scope :expired_holds, ->(now = Time.current) { pending.where(expires_at: ..now) }
  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }
  scope :on_local_date, ->(date, zone) {
    day = date.in_time_zone(zone)
    overlapping(day.beginning_of_day, day.end_of_day)
  }

  # Confirmed bookings of customers with an account that start within REMINDER_LEAD_TIME and were not
  # reminded yet. Bookings made less than REMINDER_LEAD_TIME ahead just got their confirmation, so they are skipped.
  scope :due_for_reminder, ->(now = Time.current) {
    kind_reservation.confirmed.where.not(user_id: nil).where(reminder_sent_at: nil)
                    .where(starts_at: now..(now + REMINDER_LEAD_TIME))
                    .where("bookings.created_at <= bookings.starts_at - make_interval(secs => ?)", REMINDER_LEAD_TIME.to_i)
  }

  normalizes :customer_phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :customer_name, with: ->(name) { name.squish.presence }

  after_commit :refresh_live_schedules
  after_commit :tell_waitlist, on: :update
  # The booking's history, oldest first (see #record_events).
  has_many :events, -> { order(:id) }, class_name: "BookingEvent", inverse_of: :booking
  after_create :record_creation
  after_update :record_events

  before_validation :assign_code, on: :create
  before_validation :assign_block_source, on: :create, if: :kind_block?
  before_validation :copy_customer_from_user, if: :kind_reservation?
  before_validation :apply_price, if: :needs_pricing?

  validates :starts_at, :ends_at, presence: true
  validates :customer_name, presence: true, length: { maximum: 100 }, if: :kind_reservation?
  # Without a phone only once its customer deleted their account (Accounts::Deletion).
  validates :customer_phone, presence: true, format: { with: PhoneNumber::FORMAT }, if: -> { kind_reservation? && !user&.deleted_at }
  validates :user, presence: true, if: :source_online?
  validates :total_amount_vnd, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true, if: :pending?
  validate :time_range_on_slot_grid
  validate :price_available
  validate :court_and_venue_bookable, if: :schedule_changed?
  validate :within_opening_hours, if: -> { kind_reservation? && schedule_changed? }
  validate :within_customer_policy, if: -> { kind_reservation? && source_online? && schedule_changed? && !staff_change }
  validate :slot_free, if: -> { schedule_changed? && holds_slot? }
  validate :within_price_cap, if: -> { price_cap_vnd }

  # Makes bookings on the same courts wait for each other until the end of the current transaction.
  # Without it, two requests inserting the same slot at the same moment each wait for the other while
  # checking the exclusion constraint, and Postgres aborts one with a deadlock. With it, the second
  # request runs after the first commits and gets the friendly slot_taken error from slot_free.
  # Courts are locked in id order so that bookings on several courts cannot deadlock each other.
  def self.lock_courts!(court_ids)
    court_ids.compact.map(&:to_i).uniq.sort.each do |court_id|
      connection.execute(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?, ?)", COURT_LOCK_NAMESPACE, court_id ]))
    end
  end

  # Holds past their expiry still sit in the "bookings_no_overlap" exclusion constraint until deleted, so they
  # are deleted while the courts are locked, before a new booking is inserted. A recurring job tidies up the rest.
  # Bookings waiting for a transfer (payment_id set) are cancelled rather than deleted, so a late transfer can
  # still be matched and reviewed; holds of the confirmation page (no payment) are deleted.
  def self.release_expired_holds!(court_ids = nil, now: Time.current)
    scope = expired_holds(now)
    scope = scope.where(court_id: court_ids) if court_ids
    scope.where.not(payment_id: nil).includes(:payment).find_each { |booking| booking.expire_payment!(now) }
    delete_holds!(scope)
  end

  # Deletes the confirmation-page holds of the scope (not the bookings waiting for a transfer).
  # delete_all skips callbacks, so the open schedules are refreshed here. Returns the number of deleted holds.
  def self.delete_holds!(scope)
    holds = scope.pending.where(payment_id: nil)
    ranges = holds.pluck(:court_id, :starts_at, :ends_at)
    return 0 if ranges.empty?

    deleted = holds.delete_all
    Schedule::Live.refresh(ranges)
    WaitlistJob.enqueue_for(ranges)
    deleted
  end

  # Use instead of #save when creating or rescheduling a booking.
  # The court lock makes the slot_free validation reliable; the exclusion constraint in the DB stays the
  # final guard (e.g. against code that skips the lock), and a deadlock is reported the same way.
  # The savepoint (requires_new) keeps any outer transaction usable after the error.
  def reserve
    self.class.transaction(requires_new: true) do
      self.class.lock_courts!([ court_id ])
      self.class.release_expired_holds!([ court_id ])
      save
    end
  rescue ActiveRecord::ExclusionViolation, ActiveRecord::Deadlocked
    errors.add(:base, :slot_just_taken)
    false
  end

  # Set while the owner or staff move a booking: the online booking rules (duration, horizon) do not apply.
  attr_accessor :staff_change
  # Set when a customer moves a paid booking: the new slot must not cost more than what was paid.
  attr_accessor :price_cap_vnd
  # Set when a series session of a month already paid is moved (Series::Move): the amount paid stays.
  attr_accessor :keep_price

  # Moves a confirmed booking (or a block) to another court and/or time, with the court locks of #reserve
  # (old and new courts) and a new price. Customers: see #reschedulable_by_customer?. Returns true when saved.
  #   booking.reschedule(court: court, starts_at: from, ends_at: to, by: current_user)
  # keep_price: the venue moves it without pricing it again (a series month already paid, see Series::Move).
  def reschedule(court:, starts_at:, ends_at:, by:, keep_price: false)
    unless by.manager? ? movable_by_staff? : reschedulable_by_customer?
      errors.add(:base, :not_reschedulable)
      return false
    end

    old_court_id = court_id
    paid_vnd = total_amount_vnd if payment_paid?
    self.class.transaction(requires_new: true) do
      self.class.lock_courts!([ old_court_id, court&.id ])
      self.class.release_expired_holds!([ old_court_id, court&.id ])
      assign_attributes(court: court, starts_at: starts_at, ends_at: ends_at, reminder_sent_at: nil)
      self.staff_change = by.manager?
      self.keep_price = keep_price && by.manager?
      # Customers moving a paid booking: not to a dearer slot, and the cheaper price is not refunded.
      self.price_cap_vnd = paid_vnd unless by.manager?
      save && (paid_vnd.nil? || by.manager? || total_amount_vnd >= paid_vnd || update_columns(total_amount_vnd: paid_vnd))
    end
  rescue ActiveRecord::ExclusionViolation, ActiveRecord::Deadlocked
    errors.add(:base, :slot_just_taken)
    false
  end

  # Customers move their own booking online until the cancellation cutoff, while it is unpaid
  # (a paid booking's price could change) and unless they are blacklisted.
  # Sessions of a regular customer's series are moved by the venue. A paid booking can be moved to a slot
  # that does not cost more (see #reschedule: no refund of the difference).
  # The owner and staff move confirmed reservations until they end, and blocks at any time.
  def movable_by_staff?(now = Time.current)
    holds_slot? && (kind_block? || (confirmed? && !ended?(now)))
  end

  def reschedulable_by_customer?(now = Time.current)
    series_id.nil? && confirmed? && cancellable_by_customer?(now) && !payment_refunded? && !CustomerProfile.blocked?(customer_phone)
  end

  # URLs use the customer-facing code (/bookings/K7Q2M9XA) instead of the sequential id.
  def to_param
    code
  end

  # Recalculates the price (e.g. after a series' agreed price changed).
  def reprice!
    apply_price
    save!
  end

  def holds_slot?(now = Time.current)
    ACTIVE_STATUSES.include?(status) && !(pending? && expires_at && expires_at <= now)
  end

  # What the customer pays for the booking: the court less its discount (tier, voucher, prepaid hours) and the
  # products picked with it.
  def charged_vnd
    total_amount_vnd - discount_vnd + items_amount_vnd
  end

  # Prices the booking without saving it (for a quote before booking).
  def quote_price
    apply_price if needs_pricing?
    self
  end

  def duration_minutes
    ((ends_at - starts_at) / 60).to_i
  end

  def cancellable_by_customer?(now = Time.current)
    kind_reservation? &&
      CUSTOMER_CANCELLABLE_STATUSES.include?(status) &&
      now <= starts_at - court.venue.cancellation_cutoff_hours.hours
  end

  # Over: played or missed, which check-in and no-show record. It can no longer be cancelled or moved.
  def ended?(now = Time.current)
    ends_at <= now
  end

  # Its customer can still rate it (Review): played, over, not too long ago, and not rated yet.
  def reviewable?(now = Time.current)
    persisted? && user.present? && review.nil? && Review.allowed?(self, user, now)
  end

  # Over without check-in or no-show: the owner and staff are reminded to record which.
  def unrecorded?(now = Time.current)
    kind_reservation? && confirmed? && ended?(now)
  end

  # A venue fault (power cut, broken court...) is known the same day, possibly after the session.
  def venue_fault_cancellable?(now = Time.current)
    kind_reservation? && payment_paid? && holds_slot? && now < starts_at.in_time_zone(court.venue.zone).end_of_day
  end

  # by: the user cancelling. Customers must cancel before the cutoff; managers can cancel until the booking
  # ends (a block at any time), and for a venue fault until the end of its day (#cancel_for_venue_fault!).
  def cancel!(by:, reason: nil, now: Time.current)
    raise ArgumentError, "Booking is already cancelled" if cancelled?
    if !by.manager? && !cancellable_by_customer?(now)
      raise ArgumentError, "Cancellation cutoff has passed"
    end
    raise ArgumentError, "Booking has ended" if kind_reservation? && ended?(now) && reason != VENUE_FAULT

    # Only a customer cancelling a confirmed booking counts towards the lock: not skipping a regular session
    # (agreed with the venue), nor giving up a booking still waiting for its transfer.
    counts_for_lock = user && by == user && series_id.nil? && reason.nil? && confirmed?
    reason ||= BookingSeries::SKIPPED if series_id # a regular customer's session: "I won't come this time"
    update!(status: :cancelled, cancelled_at: now, cancelled_by: by, cancellation_reason: reason)
    payment.update!(status: :cancelled) if payment&.awaiting? && payment.bookings.where.not(status: :cancelled).none?
    user.lock_booking_if_cancelling_too_often(court.venue, now) if counts_for_lock
  end

  # The venue could not provide the court (power cut, broken court...). A paid booking is owed back in full;
  # the owner transfers it and marks it refunded (#mark_refunded!).
  def cancel_for_venue_fault!(by:, now: Time.current)
    raise ArgumentError, "Too late for a venue fault" unless venue_fault_cancellable?(now)

    transaction do
      paid = payment_paid?
      cancel!(by: by, reason: VENUE_FAULT, now: now)
      update!(refund_vnd: charged_vnd) if paid && charged_vnd.positive?
      # Prepaid hours go back to the package (even past its expiry date, the hours stay recorded).
      package_purchase.with_lock { package_purchase.update!(minutes_left: package_purchase.minutes_left + package_minutes) } if package_purchase && package_minutes
    end
  end

  # cash: handed back from the drawer, so it comes out of the open cash shift (VH-12); otherwise by transfer.
  def mark_refunded!(by:, cash: false, now: Time.current)
    raise ArgumentError, "Nothing to refund" if refund_vnd.nil? || refunded_at

    @refund_in_cash = cash
    update!(refunded_at: now, refunded_by: by, payment_status: :refunded)
  end

  # The transfer did not arrive in time: the slot is released, the booking kept for a late transfer.
  def expire_payment!(now = Time.current)
    return unless pending? && payment

    transaction do
      update!(status: :cancelled, cancelled_at: now, cancellation_reason: PAYMENT_EXPIRED)
      payment.update!(status: :expired) if payment.awaiting? && payment.bookings.where.not(status: :cancelled).none?
    end
  end

  def check_in!(now: Time.current)
    raise ArgumentError, "Only confirmed bookings can be checked in" unless confirmed?

    update!(status: :checked_in, checked_in_at: now)
  end

  def mark_paid!(now: Time.current)
    raise ArgumentError, "Booking is already paid" unless payment_unpaid?

    update!(payment_status: :paid, paid_at: now)
  end

  def mark_no_show!
    raise ArgumentError, "Only confirmed bookings can be marked as no-show" unless confirmed?

    update!(status: :no_show)
  end

  # Undo for the owner's and staff's actions pressed by mistake: back to the state before them.
  def undo_check_in!
    raise ArgumentError, "Only checked-in bookings can be undone" unless checked_in?

    update!(status: :confirmed, checked_in_at: nil)
  end

  def undo_no_show!
    raise ArgumentError, "Only no-show bookings can be undone" unless no_show?

    update!(status: :confirmed)
  end

  def undo_payment!
    raise ArgumentError, "Only paid bookings can be undone" unless payment_paid?

    update!(payment_status: :unpaid, paid_at: nil)
  end

  private

  def record_creation
    record(:created, source: source, status: status, **slot_details(court, starts_at, ends_at), amount: total_amount_vnd)
  end

  # One event per change that matters, by Current.user (nil: the system). Paid and confirmed in the same
  # update (a transfer arriving) is one "paid" event.
  def record_events
    changes = saved_changes
    if (changes.keys & %w[court_id starts_at ends_at]).any?
      record(:rescheduled, from: slot_details(Court.find_by(id: court_id_before_last_save), starts_at_before_last_save, ends_at_before_last_save),
                           to: slot_details(court, starts_at, ends_at),
                           amount_from: total_amount_vnd_before_last_save, amount: total_amount_vnd)
    elsif changes.key?("total_amount_vnd")
      record(:price_changed, amount_from: total_amount_vnd_before_last_save, amount: total_amount_vnd)
    end

    paid_now = changes["payment_status"] == %w[unpaid paid]
    if (action = status_event(changes["status"], paid_now))
      record(action, **({ reason: cancellation_reason } if action == :cancelled).to_h)
    end
    case changes["payment_status"]
    when %w[unpaid paid]
      via = payment_id ? "transfer" : (series_id ? "series" : "cash")
      record(:paid, amount: total_amount_vnd, via: via, cash: (cash_entry(charged_vnd) if via == "cash"))
    when %w[paid unpaid] then record(:payment_undone, amount: total_amount_vnd, cash: cash_undo_entry)
    when %w[paid refunded]
      record(:refunded, amount: refund_vnd, via: @refund_in_cash ? "cash" : "transfer", cash: (cash_entry(-refund_vnd) if @refund_in_cash))
    end
    record(:refund_due, amount: refund_vnd) if changes["refund_vnd"]&.first.nil? && refund_vnd
  end

  def status_event((from, to), paid_now)
    return unless to
    return if to == "confirmed" && paid_now # told by the "paid" event

    case [ from, to ]
    in [ _, "cancelled" ] then cancellation_reason == PAYMENT_EXPIRED ? :payment_expired : :cancelled
    in [ "confirmed", "checked_in" ] then :checked_in
    in [ "checked_in", "confirmed" ] then :check_in_undone
    in [ "confirmed", "no_show" ] then :no_show
    in [ "no_show", "confirmed" ] then :no_show_undone
    in [ _, "confirmed" ] then :confirmed
    else nil
    end
  end

  # cash: { cash_shift:, cash_vnd: } when the event moves cash in the open cash shift (see CashShift).
  def record(action, cash: nil, **details)
    events.create!(action: action, actor: Current.user, details: details, **cash.to_h)
  end

  # Cash taken at the counter goes into the open cash shift, if any.
  def cash_entry(amount)
    shift = CashShift.current(court.venue, lock: true)
    { cash_shift: shift, cash_vnd: amount } if shift
  end

  # Undoing a cash payment of the open shift takes it out again; a payment of an earlier (closed) shift or a
  # transfer is left alone, so nothing is counted twice.
  def cash_undo_entry
    paid = events.where(action: "paid").reorder(id: :desc).first
    return unless paid&.cash_shift_id

    shift = CashShift.current(court.venue, lock: true)
    { cash_shift: shift, cash_vnd: -paid.cash_vnd } if shift&.id == paid.cash_shift_id
  end

  def slot_details(court, starts_at, ends_at)
    { court: court&.display_name, starts_at: starts_at&.iso8601, ends_at: ends_at&.iso8601 }
  end

  # Any change shows on the schedules of the dates involved, including where the booking was before a move.
  def refresh_live_schedules
    ranges = [ [ court_id, starts_at, ends_at ] ]
    if saved_change_to_court_id? || saved_change_to_starts_at? || saved_change_to_ends_at?
      ranges << [ court_id_before_last_save, starts_at_before_last_save, ends_at_before_last_save ]
    end
    Schedule::Live.refresh(ranges.uniq)
  end

  # A slot freed by a cancellation or a move may be what someone waits for (WaitlistEntry).
  def tell_waitlist
    if saved_change_to_status? && cancelled?
      WaitlistJob.enqueue_for([ [ court_id, starts_at, ends_at ] ])
    elsif saved_change_to_court_id? || saved_change_to_starts_at? || saved_change_to_ends_at?
      WaitlistJob.enqueue_for([ [ court_id_before_last_save, starts_at_before_last_save, ends_at_before_last_save ] ])
    end
  end

  # A status change only counts when the booking starts holding the slot again (e.g. a cancelled
  # booking is restored), not when it moves between active statuses (check-in, no-show, ...).
  def schedule_changed?
    new_record? || will_save_change_to_starts_at? || will_save_change_to_ends_at? ||
      will_save_change_to_court_id? || (will_save_change_to_status? && holds_slot? && !ACTIVE_STATUSES.include?(status_in_database))
  end

  def needs_pricing?
    kind_reservation? && court && starts_at && ends_at && !keep_price &&
      (new_record? || will_save_change_to_starts_at? || will_save_change_to_ends_at? || will_save_change_to_court_id?)
  end

  def assign_code
    return if code.present?

    loop do
      self.code = Array.new(8) { CODE_CHARS.sample(random: SecureRandom) }.join
      break unless self.class.exists?(code: code)
    end
  end

  # Blocks are always created by staff (required by the "bookings_kind_fields" constraint).
  def assign_block_source
    self.source = :staff
  end

  def copy_customer_from_user
    return unless user

    self.customer_name ||= user.full_name
    self.customer_phone ||= user.phone
  end

  def apply_price
    @missing_price_at = nil
    return unless ends_at > starts_at

    if (rate = series&.price_per_hour_vnd) # a price agreed with the regular customer
      self.total_amount_vnd = rate * duration_minutes / 60
      self.price_breakdown = [ { "from" => starts_at.iso8601, "to" => ends_at.iso8601, "price_per_hour_vnd" => rate,
                                 "amount_vnd" => total_amount_vnd, "series_id" => series.id } ]
      return
    end

    quote = Pricing::Quote.new(court: court, starts_at: starts_at, ends_at: ends_at).call
    self.total_amount_vnd = quote.total_vnd
    self.price_breakdown = quote.breakdown
  rescue Pricing::Quote::NoPriceError => e
    @missing_price_at = e.slot_start.in_time_zone(court.venue.zone)
  end

  def price_available
    errors.add(:base, :no_price, time: I18n.l(@missing_price_at, format: :slot)) if @missing_price_at
  end

  def time_range_on_slot_grid
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :after_start) unless ends_at > starts_at
    [ starts_at, ends_at ].each do |time|
      next if (time.to_r % SLOT_SECONDS).zero?

      errors.add(:base, :off_slot_grid)
      break
    end
  end

  def court_and_venue_bookable
    return unless court

    errors.add(:court, :court_inactive) if court.inactive?
    errors.add(:court, :venue_inactive) if court.venue.inactive?
  end

  def within_opening_hours
    return if court.nil? || starts_at.blank? || ends_at.blank? || ends_at <= starts_at

    venue = court.venue
    local_start = starts_at.in_time_zone(venue.zone)
    day_start = local_start.beginning_of_day
    start_minute = ((starts_at - day_start) / 60).to_i
    end_minute = ((ends_at - day_start) / 60).to_i
    opening = venue.opening_hour_for(local_start.to_date)

    if opening.nil? || !opening.covers?(start_minute, end_minute)
      errors.add(:base, :outside_opening_hours)
    end
  end

  def within_customer_policy
    return if court.nil? || starts_at.blank? || ends_at.blank? || ends_at <= starts_at

    venue = court.venue
    now = Time.current
    errors.add(:starts_at, :not_in_future) if starts_at <= now
    errors.add(:starts_at, :beyond_horizon, count: venue.booking_horizon_days) if starts_at > now + venue.booking_horizon_days.days
    unless duration_minutes.between?(venue.min_booking_minutes, venue.max_booking_minutes)
      errors.add(:base, :duration_out_of_range, min: venue.min_booking_minutes, max: venue.max_booking_minutes)
    end
  end

  def within_price_cap
    errors.add(:base, :dearer_than_paid, paid: ActiveSupport::NumberHelper.number_to_delimited(price_cap_vnd, delimiter: ".")) if total_amount_vnd > price_cap_vnd
  end

  def slot_free
    return if court_id.nil? || starts_at.blank? || ends_at.blank?

    clash = Booking.holding_slot.where(court_id: court_id).where.not(id: id).overlapping(starts_at, ends_at)
    errors.add(:base, :slot_taken) if clash.exists?
  end
end
