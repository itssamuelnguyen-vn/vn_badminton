class User < ApplicationRecord
  # :confirmable lets unverified accounts sign in (config.allow_unconfirmed_access_for = nil);
  # they only cannot book online until the email is verified (BookingsController).
  # :timeoutable signs everyone out after config.timeout_in without activity. There is no :rememberable:
  # a "remember me" cookie would keep the session alive past the timeout.
  devise :database_authenticatable, :registerable, :recoverable, :validatable, :confirmable, :timeoutable

  # Sign-in field that accepts either an email or a phone number.
  attr_writer :login
  # The "I agree to the privacy policy" box of the sign-up form.
  attr_accessor :privacy_consent

  # admin: the owner (everything). staff: runs the day-to-day, without money (reports), prices, settings or staff.
  enum :role, { customer: "customer", staff: "staff", admin: "admin" }, default: :customer, validate: true

  # The optional profile (TK-10): shown in the app and on the account page, never required.
  enum :gender, { male: "male", female: "female", other: "other" }, prefix: true, validate: { allow_nil: true }
  enum :skill_level, { beginner: "beginner", intermediate: "intermediate", advanced: "advanced", expert: "expert" },
       prefix: :skill, validate: { allow_nil: true }

  AVATAR_TYPES = %w[image/jpeg image/png image/webp].freeze
  AVATAR_MAX_BYTES = 2.megabytes
  has_one_attached :avatar

  has_many :bookings, dependent: :restrict_with_error
  has_many :created_bookings, class_name: "Booking", foreign_key: :created_by_id,
                              inverse_of: :created_by, dependent: :restrict_with_error
  has_many :cancelled_bookings, class_name: "Booking", foreign_key: :cancelled_by_id,
                                inverse_of: :cancelled_by, dependent: :restrict_with_error

  belongs_to :deletion_requested_by, class_name: "User", optional: true
  has_many :api_tokens, dependent: :delete_all
  has_many :series_requests, dependent: :delete_all
  has_many :waitlist_entries, dependent: :delete_all
  has_many :reviews, dependent: :delete_all
  has_many :package_purchases, dependent: :restrict_with_error

  # A new password signs the mobile app out too (the web sessions already are, by Devise).
  after_update { api_tokens.delete_all if saved_change_to_encrypted_password? }

  before_create { self.privacy_accepted_at = Time.current if privacy_consent == "1" }

  # Not deleted, nor waiting to be (Accounts::Deletion).
  scope :active, -> { where(deletion_requested_at: nil) }

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
  validates :birth_year, numericality: { only_integer: true, greater_than_or_equal_to: 1900,
                                         less_than_or_equal_to: ->(_) { Date.current.year } }, allow_nil: true
  validate :avatar_is_a_small_image

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
  # A regular customer's series sessions (agreed with the venue) do not count.
  def upcoming_bookings(now = Time.current)
    bookings.kind_reservation.where(series_id: nil).where(status: %w[pending confirmed checked_in]).where("ends_at > ?", now)
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

  # Devise checks it on every request: an account whose deletion was asked is signed out everywhere at once.
  def active_for_authentication?
    super && deletion_requested_at.nil?
  end

  def inactive_message
    deletion_requested_at ? :account_deleted : super
  end

  # A base error, so the message reads as a sentence instead of starting with the field name.
  def privacy_consent_given
    errors.add(:base, :privacy_consent_required) if !privacy_consent.nil? && privacy_consent != "1"
  end

  # The type is read from the first bytes of the file, not from its name or what the browser or app says.
  def avatar_is_a_small_image
    return unless avatar.attached? && (change = attachment_changes["avatar"])

    if AVATAR_TYPES.exclude?(sniffed_content_type(change.attachable) || avatar.blob.content_type)
      errors.add(:avatar, :invalid_type)
    elsif avatar.blob.byte_size > AVATAR_MAX_BYTES
      errors.add(:avatar, :too_big, size: AVATAR_MAX_BYTES / 1.megabyte)
    end
  end

  def sniffed_content_type(attachable)
    io = attachable.is_a?(Hash) ? attachable[:io] : (attachable.to_io if attachable.respond_to?(:to_io))
    return unless io

    head = io.read(64).to_s
    io.rewind
    Marcel::MimeType.for(StringIO.new(head))
  end

  # Devise emails go through the job queue like the other emails (the job keeps the current locale).
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  # Users who can run the venue day to day: the owner and the staff.
  def manager?
    admin? || staff?
  end

  # Prices, settings, revenue reports and staff accounts.
  def owner?
    admin?
  end
end
