class Booking < ApplicationRecord
  SLOT_SECONDS = 30 * 60
  # Must match the WHERE clause of the "bookings_no_overlap" exclusion constraint.
  ACTIVE_STATUSES = %w[pending confirmed checked_in completed no_show].freeze
  CUSTOMER_CANCELLABLE_STATUSES = %w[pending confirmed].freeze
  CODE_CHARS = [ *"A".."Z", *"0".."9" ] - %w[O 0 I 1] # drop characters that are easy to confuse over the phone

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
  has_one :venue, through: :court

  scope :holding_slot, -> { where(status: ACTIVE_STATUSES) }
  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }
  scope :on_local_date, ->(date, zone) {
    day = date.in_time_zone(zone)
    overlapping(day.beginning_of_day, day.end_of_day)
  }

  normalizes :customer_phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :customer_name, with: ->(name) { name.squish.presence }

  before_validation :assign_code, on: :create
  before_validation :assign_block_source, on: :create, if: :kind_block?
  before_validation :copy_customer_from_user, if: :kind_reservation?
  before_validation :apply_price, if: :needs_pricing?

  validates :starts_at, :ends_at, presence: true
  validates :customer_name, presence: true, length: { maximum: 100 }, if: :kind_reservation?
  validates :customer_phone, presence: true, format: { with: PhoneNumber::FORMAT }, if: :kind_reservation?
  validates :user, presence: true, if: :source_online?
  validates :total_amount_vnd, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true, if: :pending?
  validate :time_range_on_slot_grid
  validate :price_available
  validate :court_and_venue_bookable, if: :schedule_changed?
  validate :within_opening_hours, if: -> { kind_reservation? && schedule_changed? }
  validate :within_customer_policy, if: -> { kind_reservation? && source_online? && schedule_changed? }
  validate :slot_free, if: -> { schedule_changed? && holds_slot? }

  # Use instead of #save when creating or rescheduling a booking.
  # The slot_free validation is only a "soft" check that produces a friendly error; when two
  # requests arrive at the same time, the exclusion constraint in the DB is the final guard.
  # The savepoint (requires_new) keeps any outer transaction usable after the error.
  def reserve
    self.class.transaction(requires_new: true) { save }
  rescue ActiveRecord::ExclusionViolation
    errors.add(:base, :slot_just_taken)
    false
  end

  def holds_slot?
    ACTIVE_STATUSES.include?(status)
  end

  def duration_minutes
    ((ends_at - starts_at) / 60).to_i
  end

  def cancellable_by_customer?(now = Time.current)
    kind_reservation? &&
      CUSTOMER_CANCELLABLE_STATUSES.include?(status) &&
      now <= starts_at - court.venue.cancellation_cutoff_hours.hours
  end

  # by: the user cancelling. Customers must cancel before the cutoff; managers can cancel at any time.
  def cancel!(by:, reason: nil, now: Time.current)
    raise ArgumentError, "Booking is already cancelled" if cancelled?
    if !by.manager? && !cancellable_by_customer?(now)
      raise ArgumentError, "Cancellation cutoff has passed"
    end

    update!(status: :cancelled, cancelled_at: now, cancelled_by: by, cancellation_reason: reason)
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

  private

  # A status change only counts when the booking starts holding the slot again (e.g. a cancelled
  # booking is restored), not when it moves between active statuses (check-in, no-show, ...).
  def schedule_changed?
    new_record? || will_save_change_to_starts_at? || will_save_change_to_ends_at? ||
      will_save_change_to_court_id? || (will_save_change_to_status? && holds_slot? && !ACTIVE_STATUSES.include?(status_in_database))
  end

  def needs_pricing?
    kind_reservation? && court && starts_at && ends_at &&
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

  def slot_free
    return if court_id.nil? || starts_at.blank? || ends_at.blank?

    clash = Booking.holding_slot.where(court_id: court_id).where.not(id: id).overlapping(starts_at, ends_at)
    errors.add(:base, :slot_taken) if clash.exists?
  end
end
