class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  # Sign-in field that accepts either an email or a phone number.
  attr_writer :login
  # The "I agree to the privacy policy" box of the sign-up form.
  attr_accessor :privacy_consent

  enum :role, { customer: "customer", admin: "admin" }, default: :customer, validate: true

  has_many :bookings, dependent: :restrict_with_error
  has_many :created_bookings, class_name: "Booking", foreign_key: :created_by_id,
                              inverse_of: :created_by, dependent: :restrict_with_error
  has_many :cancelled_bookings, class_name: "Booking", foreign_key: :cancelled_by_id,
                                inverse_of: :cancelled_by, dependent: :restrict_with_error

  before_create { self.privacy_accepted_at = Time.current if privacy_consent == "1" }

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :full_name, with: ->(name) { name.squish }

  # Email presence, format and uniqueness come from Devise's :validatable.
  validates :phone, format: { with: PhoneNumber::FORMAT }, uniqueness: true, allow_nil: true
  # Online bookings copy the customer's phone, so customers must have one.
  validates :phone, presence: true, if: :customer?
  validates :full_name, presence: true, length: { maximum: 100 }
  # Only checked when the box is sent (the sign-up form); accounts made by seeds or the console have no box.
  validate :privacy_consent_given, on: :create
  # The language of emails sent outside of a request (reminders, cancellations by the owner).
  validates :locale, inclusion: { in: -> { I18n.available_locales.map(&:to_s) } }

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

  # Bookings that count towards Venue#max_upcoming_bookings: not finished yet and not cancelled.
  def upcoming_bookings(now = Time.current)
    bookings.kind_reservation.where(status: %w[pending confirmed checked_in]).where("ends_at > ?", now)
  end

  # Customers who cancel too often in one day cannot book online for a while (Venue#cancellation_lock_days).
  def booking_locked?(now = Time.current)
    booking_locked_until.present? && booking_locked_until > now
  end

  # Cancellations the customer made themselves on the venue's current day.
  def cancellations_today(venue, now = Time.current)
    bookings.where(cancelled_by: self, cancelled_at: now.in_time_zone(venue.zone).all_day).count
  end

  # Called after the customer cancels a booking.
  def lock_booking_if_cancelling_too_often(venue, now = Time.current)
    return if manager? || cancellations_today(venue, now) < venue.cancellation_lock_threshold

    update_column(:booking_locked_until, now + venue.cancellation_lock_days.days)
  end

  def unlock_booking
    update_column(:booking_locked_until, nil)
  end

  # Keeps the language the customer last used, so later emails are in that language.
  def remember_locale(locale)
    locale = locale.to_s
    update_column(:locale, locale) if locale != self.locale && I18n.available_locales.map(&:to_s).include?(locale)
  end

  def login
    @login || email
  end

  # A base error, so the message reads as a sentence instead of starting with the field name.
  def privacy_consent_given
    errors.add(:base, :privacy_consent_required) if !privacy_consent.nil? && privacy_consent != "1"
  end

  # Users who can manage the venue (currently only the owner).
  def manager?
    admin?
  end
end
