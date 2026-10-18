# What the venue knows about a customer, by phone number: a private note, and the blacklist.
# A blacklisted customer cannot book online (BookingBatch); the owner and staff can still book for them.
class CustomerProfile < ApplicationRecord
  belongs_to :blocked_by, class_name: "User", optional: true

  normalizes :phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :note, :blocked_reason, with: ->(text) { text.strip.presence }

  validates :phone, presence: true, format: { with: PhoneNumber::FORMAT }, uniqueness: true
  validates :blocked_reason, length: { maximum: 200 }
  validates :note, length: { maximum: 2000 }

  scope :blocked, -> { where.not(blocked_at: nil) }

  def self.blocked?(phone)
    phone.present? && blocked.exists?(phone: PhoneNumber.normalize(phone))
  end

  def blocked?
    blocked_at.present?
  end
  alias_method :blocked, :blocked? # for the form's check box

  def block(by:, reason:, now: Time.current)
    self.blocked_at ||= now
    self.blocked_by ||= by
    self.blocked_reason = reason
  end

  def unblock
    self.blocked_at = nil
    self.blocked_by = nil
    self.blocked_reason = nil
  end
end
