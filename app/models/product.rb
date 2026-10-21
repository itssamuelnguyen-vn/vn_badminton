# Something customers add to a booking: racket rental, shuttlecocks, a drink. Set up by the owner
# (Admin::ProductsController); picked on the confirmation step and paid with the booking's transfer.
class Product < ApplicationRecord
  belongs_to :venue
  has_many :booking_items, dependent: :restrict_with_error

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  normalizes :name, :name_en, with: ->(name) { name.squish.presence }

  validates :name, presence: true, length: { maximum: 60 }
  validates :name_en, length: { maximum: 60 }
  validates :price_vnd, numericality: { only_integer: true, greater_than: 0 }
  validate { errors.add(:price_vnd, :not_multiple_of_1000) if price_vnd && price_vnd % 1000 != 0 }

  def display_name(locale = I18n.locale)
    (locale.to_s == "en" && name_en.presence) || name
  end
end
