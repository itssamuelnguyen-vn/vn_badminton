# A booking a member shows to one of their groups, with how many players split it (the app shows each one's share).
class GroupShare < ApplicationRecord
  belongs_to :group
  belongs_to :booking
  belongs_to :shared_by, class_name: "User"

  validates :players, numericality: { only_integer: true, in: 1..50 }
  validates :booking_id, uniqueness: { scope: :group_id }
  validate :own_booking_in_own_group, on: :create

  # Rounded up to the thousand, as people pay each other back.
  def per_player_vnd
    (booking.charged_vnd.to_f / players / 1000).ceil * 1000
  end

  private

  def own_booking_in_own_group
    errors.add(:booking, :not_yours) unless booking && booking.user_id == shared_by_id
    errors.add(:group, :not_member) unless group && group.memberships.exists?(user_id: shared_by_id)
  end
end
