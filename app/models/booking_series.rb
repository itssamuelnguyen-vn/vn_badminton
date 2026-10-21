# A regular customer's weekly bookings ("khách cố định"): the same courts and time on some days of the week,
# between two dates. Each session is an ordinary Booking (series_id), so the board, reminders, live refresh
# and the overlap checks all apply. Paid at the start of each calendar month (BookingSeriesPeriod); a session
# the customer skips is released for others and credited to the next unpaid month if someone else plays it.
#
#   series.dates                 # => the session dates, Monday... in order
#   series.slots(dates)          # => [[court, starts_at, ends_at], ...]
#   series.billing(month)        # => Series::Billing for that calendar month
class BookingSeries < ApplicationRecord
  # Why a session was cancelled; decides what the customer gets back (see SeriesRefundJob).
  SKIPPED = "series_skip"        # the customer will not come: refunded if someone else plays that time
  VENUE_CLOSED = "venue_closed"  # the venue cancelled (holiday, maintenance): refunded in full
  ENDED = "series_ended"         # the series stopped early: not refunded

  belongs_to :user, optional: true
  belongs_to :created_by, class_name: "User"
  has_many :bookings, foreign_key: :series_id, inverse_of: :series, dependent: :restrict_with_error
  has_many :periods, class_name: "BookingSeriesPeriod", foreign_key: :series_id, inverse_of: :series, dependent: :restrict_with_error
  has_many :payments, foreign_key: :series_id, inverse_of: :series, dependent: :restrict_with_error

  normalizes :customer_phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :customer_name, with: ->(name) { name.squish.presence }
  normalizes :note, with: ->(note) { note.strip.presence }

  before_validation { self.user ||= User.find_by(phone: customer_phone) if customer_phone.present? }

  validates :customer_name, presence: true, length: { maximum: 100 }
  validates :customer_phone, presence: true, format: { with: PhoneNumber::FORMAT }
  validates :court_ids, :days_of_week, :starts_on, :ends_on, presence: true
  validates :start_minute, numericality: { only_integer: true, in: 0..1410 }
  validates :end_minute, numericality: { only_integer: true, in: 30..1440 }
  validates :price_per_hour_vnd, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :ranges_valid

  # A customer's series still worth showing: those ending last month or later.
  scope :shown_to, ->(user, today = Venue.main.today) { where(user: user).where(ends_on: today.beginning_of_month.prev_month..).order(:starts_on) }

  def venue
    courts.first&.venue || Venue.main
  end

  def courts
    Court.where(id: court_ids).order(:position, :id)
  end

  # Session dates between from and to (the series' own dates by default).
  def dates(from: starts_on, to: ends_on)
    from = [ from, starts_on ].max
    to = [ to, ends_on ].min
    return [] if from > to

    (from..to).select { |date| days_of_week.include?(date.wday) }
  end

  def slots(dates)
    zone = venue.zone
    dates.flat_map do |date|
      day = zone.local(date.year, date.month, date.day)
      courts.map { |court| [ court, day + start_minute.minutes, day + end_minute.minutes ] }
    end
  end

  def duration_minutes
    end_minute - start_minute
  end

  def billing(month)
    Series::Billing.new(self, month)
  end

  # Months with sessions, first to last.
  def months
    dates.map(&:beginning_of_month).uniq
  end

  # The months the customer sees a bill for: last month and later.
  def billed_months(today = venue.today)
    months.select { |month| month >= today.beginning_of_month.prev_month }
  end

  private

  def ranges_valid
    errors.add(:ends_on, :before_starts_on) if starts_on && ends_on && ends_on < starts_on
    errors.add(:end_minute, :after_start) if start_minute && end_minute && end_minute <= start_minute
    errors.add(:base, :off_slot_grid) if [ start_minute, end_minute ].compact.any? { |m| m % 30 != 0 }
    errors.add(:days_of_week, :invalid_days) if days_of_week.present? && !days_of_week.all? { |d| (0..6).cover?(d) }
    errors.add(:price_per_hour_vnd, :not_multiple_of_1000) if price_per_hour_vnd && price_per_hour_vnd % 1000 != 0
    errors.add(:ends_on, :too_far) if starts_on && ends_on && ends_on > starts_on + 1.year
  end
end
