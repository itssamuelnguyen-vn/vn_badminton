# "Tell me when it frees up": a customer waiting for a time range on any court. When a booking or hold that
# overlaps it is cancelled or moved away, WaitlistJob checks whether some court is now free for the whole range
# and emails everyone waiting for it (first to book gets it). Entries end once notified or once the range starts.
class WaitlistEntry < ApplicationRecord
  MAX_PER_USER = 5

  belongs_to :user

  scope :waiting, ->(now = Time.current) { where(notified_at: nil).where("starts_at > ?", now) }
  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }

  validates :starts_at, :ends_at, presence: true
  validate :range_valid, on: :create
  validate :not_too_many, on: :create

  # The courts free for the whole range right now (bookings, holds, blocks and opening hours considered).
  def free_courts(venue = Venue.main, now = Time.current)
    taken = Booking.holding_slot(now).where(court: venue.courts.active).overlapping(starts_at, ends_at).distinct.pluck(:court_id)
    venue.courts.active.reject { |court| taken.include?(court.id) }
  end

  private

  def range_valid
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :after_start) unless ends_at > starts_at
    errors.add(:starts_at, :not_in_future) unless starts_at > Time.current
    errors.add(:base, :off_slot_grid) unless [ starts_at, ends_at ].all? { |time| (time.to_r % Booking::SLOT_SECONDS).zero? }
  end

  def not_too_many
    errors.add(:base, :too_many, count: MAX_PER_USER) if user && user.waitlist_entries.waiting.count >= MAX_PER_USER
  end
end
