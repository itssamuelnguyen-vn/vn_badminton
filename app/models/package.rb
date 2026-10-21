# Prepaid hours the owner sells (e.g. 10 hours for less than 10 single hours), to use within valid_days of the
# purchase, optionally only between start_minute and end_minute (e.g. off-peak). See PackagePurchase.
class Package < ApplicationRecord
  belongs_to :venue
  has_many :purchases, class_name: "PackagePurchase", dependent: :restrict_with_error

  scope :active, -> { where(active: true) }

  normalizes :name, :name_en, with: ->(name) { name.squish.presence }

  validates :name, presence: true, length: { maximum: 60 }
  validates :name_en, length: { maximum: 60 }
  validates :minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :price_vnd, numericality: { only_integer: true, greater_than: 0 }
  validates :valid_days, numericality: { only_integer: true, in: 1..730 }
  validate do
    errors.add(:minutes, :not_multiple_of_30) if minutes && minutes % 30 != 0
    errors.add(:price_vnd, :not_multiple_of_1000) if price_vnd && price_vnd % 1000 != 0
    errors.add(:end_minute, :after_start) if start_minute && end_minute && end_minute <= start_minute
    errors.add(:start_minute, :both_or_none) if start_minute.nil? != end_minute.nil?
  end

  def display_name(locale = I18n.locale)
    (locale.to_s == "en" && name_en.presence) || name
  end
end
