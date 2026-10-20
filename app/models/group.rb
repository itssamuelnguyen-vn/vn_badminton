# Customers who play together (app only): the owner creates it and shares the invite code; members see the
# bookings shared with the group (GroupShare) and each player's share of the price. The app collects nothing.
class Group < ApplicationRecord
  MAX_MEMBERS = 20
  MAX_PER_USER = 10
  CODE_CHARS = Booking::CODE_CHARS

  belongs_to :owner, class_name: "User"
  has_many :memberships, class_name: "GroupMembership", dependent: :delete_all
  has_many :members, through: :memberships, source: :user
  has_many :shares, class_name: "GroupShare", dependent: :delete_all

  normalizes :name, with: ->(name) { name.squish.presence }

  validates :name, presence: true, length: { maximum: 50 }
  before_validation :assign_invite_code, on: :create

  def self.find_code(code)
    find_by(invite_code: code.to_s.strip.upcase)
  end

  def self.create_for(user, name)
    group = new(owner: user, name: name)
    group.errors.add(:base, :too_many, count: MAX_PER_USER) if user.groups.count >= MAX_PER_USER
    return group if group.errors.any?

    transaction do
      group.save && group.memberships.create!(user: user)
    end
    group
  end

  def join(user)
    return true if members.include?(user)

    errors.add(:base, :full, count: MAX_MEMBERS) if memberships.count >= MAX_MEMBERS
    errors.add(:base, :too_many, count: MAX_PER_USER) if user.groups.count >= MAX_PER_USER
    errors.empty? && memberships.create!(user: user)
  end

  # Leaving: the member's shares go too. The owner leaving hands the group to the oldest member, or deletes it.
  def remove(user)
    transaction do
      memberships.where(user: user).delete_all
      shares.where(shared_by: user).delete_all
      next unless owner_id == user.id

      successor = memberships.order(:created_at).first&.user
      successor ? update!(owner: successor) : destroy!
    end
  end

  private

  def assign_invite_code
    loop do
      self.invite_code = Array.new(6) { CODE_CHARS.sample(random: SecureRandom) }.join
      break unless self.class.exists?(invite_code: invite_code)
    end
  end
end
