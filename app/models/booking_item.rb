# A product picked with a booking, at its price when picked. Booking#items_amount_vnd keeps their sum.
class BookingItem < ApplicationRecord
  MAX_QUANTITY = 20

  belongs_to :booking
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, in: 1..MAX_QUANTITY }

  def amount_vnd
    unit_price_vnd * quantity
  end

  def display_name(locale = I18n.locale)
    product&.display_name(locale) || name
  end
end
