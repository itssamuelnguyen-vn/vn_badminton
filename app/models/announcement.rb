# News the owner shows on the booking page and in the app, between two dates (holiday closing, an offer...).
class Announcement < ApplicationRecord
  TONES = %w[info offer warning].freeze

  belongs_to :venue

  scope :current, ->(date) { where(starts_on: ..date, ends_on: date..).order(:starts_on, :id) }

  normalizes :title, :title_en, with: ->(text) { text.squish.presence }
  normalizes :body, :body_en, with: ->(text) { text.strip.presence }

  validates :title, presence: true, length: { maximum: 100 }
  validates :title_en, length: { maximum: 100 }
  validates :body, :body_en, length: { maximum: 1000 }
  validates :starts_on, :ends_on, presence: true
  validates :tone, inclusion: { in: TONES }
  validate { errors.add(:ends_on, :before_starts_on) if starts_on && ends_on && ends_on < starts_on }

  def display_title(locale = I18n.locale)
    (locale.to_s == "en" && title_en.presence) || title
  end

  def display_body(locale = I18n.locale)
    (locale.to_s == "en" && body_en.presence) || body
  end
end
