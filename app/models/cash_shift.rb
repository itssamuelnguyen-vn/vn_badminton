# The cash drawer of one shift ("ca làm"): opened with the cash in the drawer, closed by counting it.
# At most one shift is open at a time (unique index). Cash recorded while it is open points at it:
# - a booking paid in cash ("Đã thu"): its BookingEvent "paid" with cash_vnd = what the customer paid;
# - undoing that payment in the same shift: its BookingEvent "payment_undone" with cash_vnd = minus the same,
#   so a payment and its undo cancel out. Undoing a payment of an earlier shift does not touch this shift
#   (that shift is closed and its count stands);
# - a series month paid in cash (BookingSeriesPeriod.cash_shift_id): its due amount.
# Expected at the close = opening + collected; the difference (counted - expected) needs a note when not 0.
#
#   shift = CashShift.open!(venue: venue, by: staff, opening_vnd: 500_000)
#   shift.collected_vnd                       # => cash recorded so far
#   shift.close!(by: staff, counted_vnd: 1_200_000, note: nil)
class CashShift < ApplicationRecord
  belongs_to :venue
  belongs_to :opened_by, class_name: "User"
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :events, class_name: "BookingEvent", dependent: :restrict_with_error
  has_many :series_periods, class_name: "BookingSeriesPeriod", dependent: :restrict_with_error

  scope :open, -> { where(closed_at: nil) }
  scope :closed, -> { where.not(closed_at: nil) }

  normalizes :note, with: ->(note) { note.strip.presence }

  validates :opening_vnd, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :counted_vnd, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }, if: :closed?
  validates :note, length: { maximum: 500 }
  validates :note, presence: true, if: -> { closed? && difference_vnd&.nonzero? }
  validate :one_open_shift, on: :create

  # The open shift, locked FOR SHARE when cash is recorded: a close waits for the payments being recorded,
  # and a payment recorded after the close no longer finds it.
  def self.current(venue, lock: false)
    shifts = open.where(venue_id: venue.id)
    (lock ? shifts.lock("FOR SHARE") : shifts).first
  end

  # Returns the shift (with errors when not saved).
  def self.open!(venue:, by:, opening_vnd:, now: Time.current)
    create(venue: venue, opened_by: by, opened_at: now, opening_vnd: opening_vnd)
  rescue ActiveRecord::RecordNotUnique
    new(venue: venue, opening_vnd: opening_vnd).tap { |shift| shift.errors.add(:base, :already_open) }
  end

  def closed?
    closed_at.present?
  end

  # Cash recorded in the shift so far (stored at the close).
  def collected_vnd
    return self[:collected_vnd] if closed?

    events.sum(:cash_vnd) + series_periods.sum("amount_vnd - credit_vnd").to_i
  end

  def expected_vnd
    closed? ? self[:expected_vnd] : opening_vnd + collected_vnd
  end

  # Counts the drawer. Locked, so cash being recorded meanwhile is either in the sum or after the close.
  # Returns true when closed; false with errors (e.g. no note for a difference).
  def close!(by:, counted_vnd:, note:, now: Time.current)
    closed = with_lock do
      if closed?
        errors.add(:base, :already_closed)
        next false
      end

      collected = collected_vnd
      assign_attributes(closed_by: by, closed_at: now, collected_vnd: collected, expected_vnd: opening_vnd + collected,
                        counted_vnd: counted_vnd, difference_vnd: counted_vnd && counted_vnd - opening_vnd - collected, note: note)
      save || raise(ActiveRecord::Rollback)
    end
    closed || restore_closing
  end

  # What was collected, newest first: [[time, booking or series, amount, actor, action], ...], for the shift's page.
  # action: "paid", "payment_undone" or "refunded" (a booking's event), "series_paid".
  def cash_lines
    from_events = events.includes(:actor, booking: :court).map { |e| [ e.created_at, e.booking, e.cash_vnd, e.actor, e.action ] }
    from_series = series_periods.includes(:series, :paid_by).map { |p| [ p.paid_at, p, p.due_vnd, p.paid_by, "series_paid" ] }
    (from_events + from_series).sort_by { |line| -line.first.to_i }
  end

  private

  def one_open_shift
    errors.add(:base, :already_open) if venue && CashShift.open.where(venue_id: venue_id).exists?
  end

  # A failed close leaves the shift open, as it is in the database (the typed count and note stay for the form).
  def restore_closing
    self.closed_by = nil
    self.closed_at = nil
    %i[collected_vnd expected_vnd difference_vnd].each { |column| self[column] = nil }
    false
  end
end
