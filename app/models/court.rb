class Court < ApplicationRecord
  enum :status, { active: "active", inactive: "inactive" }, default: :active, validate: true

  belongs_to :venue
  has_many :bookings, dependent: :restrict_with_error
  has_many :price_rules, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 50 },
                   uniqueness: { scope: :venue_id, case_sensitive: false }
  validates :position, numericality: { only_integer: true }

  # Courts named with a bare number ("3") are shown as "Sân 3" / "Court 3" in the current locale;
  # any other name ("VIP") is shown as entered.
  def display_name
    name.match?(/\A\d+\z/) ? I18n.t("courts.numbered", number: name) : name
  end
end
