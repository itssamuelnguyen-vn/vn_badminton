# A discount code (Voucher) for online bookings: a percentage (capped by max_discount_vnd) or an amount off the
# court price, between two dates, optionally only on some days and at some times (every booking must start and
# end inside them), for orders from min_amount_vnd. Limited in total (usage_limit) and per customer.
# A redemption counts while its payment is awaiting or paid (an expired transfer gives the use back).
class Voucher < ApplicationRecord
  KINDS = %w[percent amount].freeze

  belongs_to :venue
  has_many :redemptions, class_name: "VoucherRedemption", dependent: :restrict_with_error

  normalizes :code, with: ->(code) { code.strip.upcase.delete(" ") }
  normalizes :description, with: ->(text) { text.squish.presence }
  normalizes :days_of_week, with: ->(days) { Array(days).compact_blank.map(&:to_i).uniq.sort.presence }

  validates :code, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\A[A-Z0-9_-]{3,20}\z/ }
  validates :kind, inclusion: { in: KINDS }
  validates :value, numericality: { only_integer: true, greater_than: 0 }
  validates :value, numericality: { less_than_or_equal_to: 100 }, if: -> { kind == "percent" }
  validates :max_discount_vnd, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :min_amount_vnd, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :usage_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :per_user_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :valid_from, :valid_until, presence: true
  validate :ranges_valid

  def self.find_code(code)
    find_by(code: code.to_s.strip.upcase.delete(" "))
  end

  def uses(scope = redemptions)
    scope.joins(:payment).where(payments: { status: %w[awaiting paid] }).count
  end

  # Why the code cannot be used for these bookings (court price total), or nil.
  def problem(user, bookings, court_vnd, today: venue.today)
    zone = venue.zone
    return :inactive unless active
    return :expired unless (valid_from..valid_until).cover?(today)
    return :used_up if usage_limit && uses >= usage_limit
    return :used_by_you if uses(redemptions.where(user: user)) >= per_user_limit
    return :min_amount if court_vnd < min_amount_vnd
    return :wrong_day if days_of_week.present? && bookings.any? { |b| !days_of_week.include?(b.starts_at.in_time_zone(zone).wday) }

    :wrong_time if start_minute && bookings.any? { |b| !within_hours?(b, zone) }
  end

  def discount_for(court_vnd)
    off = kind == "percent" ? court_vnd * value / 100 : value
    off = [ off, max_discount_vnd ].compact.min
    [ off.to_i / 1000 * 1000, court_vnd ].min # whole thousands, never more than the price
  end

  private

  def within_hours?(booking, zone)
    local = booking.starts_at.in_time_zone(zone)
    start = local.hour * 60 + local.min
    start >= start_minute && start + booking.duration_minutes <= end_minute
  end

  def ranges_valid
    errors.add(:valid_until, :before_valid_from) if valid_from && valid_until && valid_until < valid_from
    errors.add(:end_minute, :after_start) if start_minute && end_minute && end_minute <= start_minute
    errors.add(:start_minute, :both_or_none) if start_minute.nil? != end_minute.nil?
    errors.add(:days_of_week, :invalid_days) if days_of_week&.any? { |day| !(0..6).cover?(day) }
  end
end
