class Venue < ApplicationRecord
  enum :status, { active: "active", inactive: "inactive" }, default: :active, validate: true

  has_many :opening_hours, dependent: :destroy
  has_many :courts, -> { order(:position, :id) }, dependent: :restrict_with_error
  has_many :price_rules, dependent: :restrict_with_error
  has_many :bookings, through: :courts

  normalizes :phone, with: ->(phone) { PhoneNumber.normalize(phone) }
  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :name, :address, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ }
  validates :phone, format: { with: PhoneNumber::FORMAT }, allow_nil: true
  # Use the full IANA list: Rails' short list does not include "Asia/Ho_Chi_Minh".
  validates :time_zone, inclusion: { in: TZInfo::Timezone.all_identifiers }
  validates :min_booking_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 30 }
  validates :max_booking_minutes, numericality: { only_integer: true, less_than_or_equal_to: 720 }
  validates :cancellation_cutoff_hours, numericality: { only_integer: true, in: 0..168 }
  validates :booking_horizon_days, numericality: { only_integer: true, in: 1..365 }
  normalizes :bank_code, :bank_account_number, with: ->(value) { value.strip.presence }
  normalizes :bank_account_name, with: ->(value) { value.strip.upcase.presence }
  validates :bank_account_number, format: { with: /\A[A-Za-z0-9]{4,19}\z/ }, allow_nil: true
  validates :max_upcoming_bookings, numericality: { only_integer: true, in: 1..50 }
  validates :cancellation_lock_threshold, numericality: { only_integer: true, in: 1..20 }
  validates :cancellation_lock_days, numericality: { only_integer: true, in: 1..90 }
  validate :booking_minutes_on_slot_grid

  # The app serves a single venue; customer pages always use it.
  def self.main
    active.order(:id).first!
  end

  # Online payment by bank transfer needs the account customers transfer to.
  def payments_enabled?
    bank_code.present? && bank_account_number.present?
  end

  def zone
    ActiveSupport::TimeZone[time_zone]
  end

  def today
    zone.today
  end

  # Dates customers can book online, from today up to the booking horizon.
  def bookable_dates
    today..(today + booking_horizon_days)
  end

  def opening_hour_for(date)
    opening_hours.detect { |oh| oh.day_of_week == date.wday }
  end

  private

  def booking_minutes_on_slot_grid
    %i[min_booking_minutes max_booking_minutes].each do |attr|
      value = public_send(attr)
      errors.add(attr, :not_multiple_of_30) if value && value % 30 != 0
    end
    if min_booking_minutes && max_booking_minutes && max_booking_minutes < min_booking_minutes
      errors.add(:max_booking_minutes, :less_than_min)
    end
  end
end
