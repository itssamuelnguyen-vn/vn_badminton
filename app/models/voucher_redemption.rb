class VoucherRedemption < ApplicationRecord
  belongs_to :voucher
  belongs_to :user
  belongs_to :payment
end
