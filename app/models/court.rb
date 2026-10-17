class Court < ApplicationRecord
  enum :status, { active: "active", inactive: "inactive" }, default: :active, validate: true

  belongs_to :venue
  has_many :bookings, dependent: :restrict_with_error
  has_many :price_rules, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 50 },
                   uniqueness: { scope: :venue_id, case_sensitive: false }
  validates :position, numericality: { only_integer: true }
end
