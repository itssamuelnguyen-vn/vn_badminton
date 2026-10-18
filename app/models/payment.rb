# Money expected by bank transfer (VietQR), confirmed by a SePay webhook (Payments::Webhook).
# purpose "bookings": the bookings made together, held (pending) until paid or until expires_at.
# purpose "series_period": one calendar month of a regular customer's series.
class Payment < ApplicationRecord
  CODE_PREFIX = "VNB"
  # How long the customer has to transfer once on the payment page (the bookings stay held meanwhile).
  WINDOW = 15.minutes
  # Transfers made in time can reach the bank's notification a little late.
  GRACE = 2.minutes
  # CODE_PREFIX followed by 8 of Booking::CODE_CHARS (A-Z and 2-9 without O and I); test/models/payment_test.rb checks it.
  CODE_PATTERN = /VNB[A-HJ-NP-Z2-9]{8}/

  enum :purpose, { bookings: "bookings", series_period: "series_period" }, prefix: :for, validate: true
  enum :status, { awaiting: "awaiting", paid: "paid", expired: "expired", cancelled: "cancelled" }, default: :awaiting, validate: true

  belongs_to :user, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :series, class_name: "BookingSeries", optional: true
  belongs_to :bank_transaction, optional: true
  has_many :bookings, dependent: :nullify

  before_validation :assign_code_and_token, on: :create
  # The payment page refreshes itself when the payment is paid, expires or is cancelled.
  after_commit { Turbo::StreamsChannel.broadcast_refresh_later_to(stream) if saved_change_to_status? }

  validates :amount_vnd, numericality: { only_integer: true, greater_than: 0 }

  def to_param
    token
  end

  def stream
    "payment:#{token}"
  end

  # Still payable: awaiting and not past the deadline (plus the grace for slow bank notifications).
  def open?(now = Time.current)
    awaiting? && (expires_at.nil? || now <= expires_at + GRACE)
  end

  # The VietQR image of the venue's account with the amount and this payment's code.
  def qr_url(venue)
    query = { acc: venue.bank_account_number, bank: venue.bank_code, amount: amount_vnd, des: code,
              template: "compact", holder: venue.bank_account_name }.compact.to_query
    "https://vietqr.app/img?#{query}"
  end

  def self.code_in(text)
    text.to_s.upcase[CODE_PATTERN]
  end

  private

  def assign_code_and_token
    self.token ||= SecureRandom.urlsafe_base64(16)
    return if code.present?

    loop do
      self.code = CODE_PREFIX + Array.new(8) { Booking::CODE_CHARS.sample(random: SecureRandom) }.join
      break unless self.class.exists?(code: code)
    end
  end
end
