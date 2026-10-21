# A customer's prepaid hours: bought by transfer (status awaiting -> active when paid), then each booking paid
# with it takes its minutes off. Usable until expires_at (valid_days after payment), only at the package's times
# if it has some. Unused hours are not refunded; a booking the customer cancels does not give its hours back,
# one the venue cancels for its own fault does.
class PackagePurchase < ApplicationRecord
  # How long the transfer can take; then the purchase is dropped.
  PAYMENT_WINDOW = 30.minutes

  enum :status, { awaiting: "awaiting", active: "active", cancelled: "cancelled" }, default: :awaiting, validate: true

  belongs_to :user
  belongs_to :package
  belongs_to :payment, optional: true
  has_many :bookings, dependent: :restrict_with_error

  scope :usable, ->(now = Time.current) { active.where("expires_at > ?", now).where("minutes_left > 0") }
  # What the customer sees of their purchases: paid ones, and those still waiting for the transfer.
  scope :listed, ->(now = Time.current) { active.or(awaiting.where(created_at: (now - PAYMENT_WINDOW)..)) }

  def self.buy!(user, package, now: Time.current)
    transaction do
      purchase = create!(user: user, package: package, name: package.name, minutes_total: package.minutes, minutes_left: package.minutes,
                         price_vnd: package.price_vnd, valid_days: package.valid_days, start_minute: package.start_minute, end_minute: package.end_minute)
      payment = Payment.create!(purpose: :package, package_purchase: purchase, user: user, created_by: user, amount_vnd: package.price_vnd,
                                expires_at: now + PAYMENT_WINDOW)
      purchase.update!(payment: payment)
      purchase
    end
  end

  # Called by Payments::Confirm when the transfer arrives.
  def activate!(now = Time.current)
    update!(status: :active, paid_at: now, expires_at: (now + valid_days.days).in_time_zone(package.venue.zone).end_of_day)
  end

  def display_name(locale = I18n.locale)
    package&.display_name(locale) || name
  end

  def expired?(now = Time.current)
    active? && expires_at <= now
  end

  # Why these bookings cannot be paid with the package, or nil.
  def problem(bookings, now = Time.current)
    return :not_usable unless active? && expires_at > now
    return :not_enough if bookings.sum(&:duration_minutes) > minutes_left
    return :expires_before if bookings.any? { |booking| booking.starts_at >= expires_at }

    :wrong_time if start_minute && bookings.any? { |booking| !within_hours?(booking) }
  end

  private

  def within_hours?(booking)
    local = booking.starts_at.in_time_zone(package.venue.zone)
    start = local.hour * 60 + local.min
    start >= start_minute && start + booking.duration_minutes <= end_minute
  end
end
