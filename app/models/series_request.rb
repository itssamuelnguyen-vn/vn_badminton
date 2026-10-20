# A customer asking for a weekly booking ("lịch cố định") from the app. Only the owner and staff create series
# (CD-01): they open the request, create the series from it (Admin::SeriesController) or decline it with a reason.
class SeriesRequest < ApplicationRecord
  MAX_PENDING = 3

  enum :status, { pending: "pending", approved: "approved", declined: "declined", cancelled: "cancelled" }, default: :pending, validate: true

  belongs_to :user
  belongs_to :series, class_name: "BookingSeries", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  normalizes :note, with: ->(note) { note.strip.presence }
  normalizes :decline_reason, with: ->(reason) { reason.squish.presence }

  validates :court_ids, :days_of_week, :starts_on, :ends_on, presence: true
  validates :start_minute, numericality: { only_integer: true, in: 0..1410 }
  validates :end_minute, numericality: { only_integer: true, in: 30..1440 }
  validates :note, length: { maximum: 500 }
  validates :decline_reason, length: { maximum: 200 }
  validate :ranges_valid, on: :create
  validate :not_too_many, on: :create

  def courts
    Court.where(id: court_ids).order(:position, :id)
  end

  # The fields of a new series built from the request (the staff can change them before creating it).
  def series_attributes
    { customer_name: user.full_name, customer_phone: user.phone, court_ids: court_ids, days_of_week: days_of_week,
      start_minute: start_minute, end_minute: end_minute, starts_on: starts_on, ends_on: ends_on, note: note }
  end

  def approve!(series, by:, now: Time.current)
    update!(status: :approved, series: series, decided_by: by, decided_at: now)
  end

  def decline!(reason, by:, now: Time.current)
    update!(status: :declined, decline_reason: reason, decided_by: by, decided_at: now)
  end

  private

  def ranges_valid
    venue = Venue.main
    errors.add(:end_minute, :after_start) if start_minute && end_minute && end_minute <= start_minute
    errors.add(:base, :off_slot_grid) if [ start_minute, end_minute ].compact.any? { |m| m % 30 != 0 }
    errors.add(:days_of_week, :invalid_days) if days_of_week.present? && !days_of_week.all? { |d| (0..6).cover?(d) }
    errors.add(:court_ids, :invalid) if court_ids.present? && venue.courts.active.where(id: court_ids).count != court_ids.uniq.size
    errors.add(:starts_on, :not_in_future) if starts_on && starts_on <= venue.today
    errors.add(:ends_on, :before_starts_on) if starts_on && ends_on && ends_on < starts_on
    errors.add(:ends_on, :too_far) if starts_on && ends_on && ends_on > starts_on + 1.year
  end

  def not_too_many
    errors.add(:base, :too_many, count: MAX_PENDING) if user && user.series_requests.pending.count >= MAX_PENDING
  end
end
