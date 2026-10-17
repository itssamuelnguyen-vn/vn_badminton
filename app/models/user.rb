class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  # Sign-in field that accepts either an email or a phone number.
  attr_writer :login

  enum :role, { customer: "customer", admin: "admin" }, default: :customer, validate: true

  has_many :bookings, dependent: :restrict_with_error
  has_many :created_bookings, class_name: "Booking", foreign_key: :created_by_id,
                              inverse_of: :created_by, dependent: :restrict_with_error
  has_many :cancelled_bookings, class_name: "Booking", foreign_key: :cancelled_by_id,
                                inverse_of: :cancelled_by, dependent: :restrict_with_error

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :full_name, with: ->(name) { name.squish }

  # Email presence, format and uniqueness come from Devise's :validatable.
  validates :phone, format: { with: PhoneNumber::FORMAT }, uniqueness: true, allow_nil: true
  # Online bookings copy the customer's phone, so customers must have one.
  validates :phone, presence: true, if: :customer?
  validates :full_name, presence: true, length: { maximum: 100 }

  # Called by Devise on sign-in. "@" means an email; anything else is treated as a phone number,
  # so "0901 234 567", "84901234567" and "+84901234567" all find the same user.
  def self.find_for_database_authentication(conditions)
    login = conditions[:login].to_s.strip
    return if login.blank?

    if login.include?("@")
      find_by(email: login.downcase)
    else
      phone = PhoneNumber.normalize(login)
      find_by(phone: phone) if phone.match?(PhoneNumber::FORMAT)
    end
  end

  def login
    @login || email
  end

  # Users who can manage the venue (currently only the owner).
  def manager?
    admin?
  end
end
