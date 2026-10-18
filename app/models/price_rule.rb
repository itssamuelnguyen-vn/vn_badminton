class PriceRule < ApplicationRecord
  belongs_to :venue
  belongs_to :court, optional: true # nil = applies to every court

  normalizes :name_en, with: ->(name) { name.squish.presence }

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :name_en, length: { maximum: 50 }
  validates :days_of_week, presence: true
  validates :start_minute, numericality: { only_integer: true, in: 0..1410 }
  validates :end_minute, numericality: { only_integer: true, in: 30..1440 }
  validates :price_per_hour_vnd, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000_000 }
  validates :priority, numericality: { only_integer: true }
  validate :days_valid, :time_range_valid, :price_rounded, :validity_range, :court_in_same_venue

  def applies_to?(court:, local_slot_start:)
    minute = local_slot_start.hour * 60 + local_slot_start.min
    date = local_slot_start.to_date

    active &&
      (court_id.nil? || court_id == court.id) &&
      days_of_week.include?(date.wday) &&
      minute >= start_minute && minute + 30 <= end_minute &&
      (valid_from.nil? || date >= valid_from) &&
      (valid_until.nil? || date <= valid_until)
  end

  # The English name on English pages when there is one, the Vietnamese name otherwise.
  def display_name
    (name_en if I18n.locale == :en) || name
  end

  def price_per_slot_vnd
    price_per_hour_vnd / 2
  end

  private

  def days_valid
    return if days_of_week.blank?

    errors.add(:days_of_week, :invalid_days) unless days_of_week.all? { |d| (0..6).cover?(d) }
  end

  def time_range_valid
    return if start_minute.nil? || end_minute.nil?

    errors.add(:end_minute, :after_start) if end_minute <= start_minute
    errors.add(:base, :off_slot_grid) if start_minute % 30 != 0 || end_minute % 30 != 0
  end

  def price_rounded
    return if price_per_hour_vnd.nil?

    errors.add(:price_per_hour_vnd, :not_multiple_of_1000) if price_per_hour_vnd % 1000 != 0
  end

  def validity_range
    return if valid_from.nil? || valid_until.nil?

    errors.add(:valid_until, :before_valid_from) if valid_until < valid_from
  end

  def court_in_same_venue
    errors.add(:court, :other_venue) if court && court.venue_id != venue_id
  end
end
