class OpeningHour < ApplicationRecord
  belongs_to :venue

  validates :day_of_week, inclusion: { in: 0..6 }, uniqueness: { scope: :venue_id }
  validates :opens_minute, numericality: { only_integer: true, in: 0..1410 }
  validates :closes_minute, numericality: { only_integer: true, in: 30..1440 }
  validate :valid_range

  # "05:30" -> 330
  def self.parse_minute(hhmm)
    h, m = hhmm.split(":").map(&:to_i)
    h * 60 + m
  end

  # 330 -> "05:30"
  def self.format_minute(minute)
    format("%02d:%02d", minute / 60, minute % 60)
  end

  def covers?(start_minute, end_minute)
    start_minute >= opens_minute && end_minute <= closes_minute
  end

  private

  def valid_range
    return if opens_minute.nil? || closes_minute.nil?

    errors.add(:closes_minute, :after_opening) if closes_minute <= opens_minute
    errors.add(:base, :off_slot_grid) if opens_minute % 30 != 0 || closes_minute % 30 != 0
  end
end
