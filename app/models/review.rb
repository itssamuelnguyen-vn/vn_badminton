# A customer's rating of a session they played: 1-5 stars and an optional comment, once per booking,
# within WINDOW after it ended. Only the owner and staff see it (Admin::ReviewsController).
class Review < ApplicationRecord
  WINDOW = 14.days

  belongs_to :booking
  belongs_to :user

  normalizes :comment, with: ->(comment) { comment.strip.presence }

  validates :rating, numericality: { only_integer: true, in: 1..5 }
  validates :comment, length: { maximum: 1000 }
  validates :booking_id, uniqueness: true
  validate :booking_reviewable, on: :create

  # Played (checked in), over, the customer's own, and not too long ago.
  def self.allowed?(booking, user, now = Time.current)
    booking.kind_reservation? && booking.user_id == user.id && booking.status.in?(%w[checked_in completed]) &&
      booking.ended?(now) && booking.ends_at > now - WINDOW
  end

  private

  def booking_reviewable
    errors.add(:base, :not_reviewable) unless booking && user && self.class.allowed?(booking, user)
  end
end
