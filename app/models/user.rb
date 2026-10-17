class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable

  enum :role, { customer: "customer", admin: "admin" }, default: :customer, validate: true

  has_many :bookings, dependent: :restrict_with_error
  has_many :created_bookings, class_name: "Booking", foreign_key: :created_by_id,
                              inverse_of: :created_by, dependent: :restrict_with_error
  has_many :cancelled_bookings, class_name: "Booking", foreign_key: :cancelled_by_id,
                                inverse_of: :cancelled_by, dependent: :restrict_with_error

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :full_name, with: ->(name) { name.squish }

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, format: { with: PhoneNumber::FORMAT }, uniqueness: true, allow_nil: true
  validates :full_name, presence: true, length: { maximum: 100 }

  # Users who can manage the venue (currently only the owner).
  def manager?
    admin?
  end
end
