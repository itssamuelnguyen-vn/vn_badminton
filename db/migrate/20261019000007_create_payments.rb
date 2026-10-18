# Online payment by bank transfer (VietQR), confirmed by SePay webhooks.
# A payment covers the bookings made together (online or by the venue for a phone customer), or one month of a
# regular customer's series. Every incoming transfer is stored once (by SePay's id); transfers that do not
# match an awaiting payment exactly (amount, code, deadline) wait for the owner in the "needs review" list.
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.string :code, null: false   # in the transfer content, e.g. VNB7K2QH9XA
      t.string :token, null: false  # the public payment page (/payments/TOKEN), for customers without an account
      t.string :purpose, null: false # bookings | series_period
      t.string :status, null: false, default: "awaiting" # awaiting | paid | expired | cancelled
      t.bigint :amount_vnd, null: false
      t.datetime :expires_at, precision: 0 # bookings only
      t.datetime :paid_at, precision: 0
      t.references :user, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :series, foreign_key: { to_table: :booking_series }
      t.date :series_month
      t.timestamps precision: 0

      t.index :code, unique: true
      t.index :token, unique: true
      t.check_constraint "code ~ '^VNB[A-Z0-9]{8}$'", name: "payments_code_format"
      t.check_constraint "purpose IN ('bookings', 'series_period')", name: "payments_purpose_valid"
      t.check_constraint "status IN ('awaiting', 'paid', 'expired', 'cancelled')", name: "payments_status_valid"
      t.check_constraint "amount_vnd > 0", name: "payments_amount_positive"
      t.check_constraint "(status = 'paid') = (paid_at IS NOT NULL)", name: "payments_paid_at_consistent"
      t.check_constraint "purpose <> 'series_period' OR (series_id IS NOT NULL AND series_month IS NOT NULL)", name: "payments_series_period_target"
      t.check_constraint "purpose <> 'bookings' OR expires_at IS NOT NULL", name: "payments_bookings_expiry"
    end

    create_table :bank_transactions do |t|
      t.bigint :sepay_id, null: false
      t.string :direction, null: false # in | out
      t.bigint :amount_vnd, null: false
      t.text :content
      t.string :gateway
      t.string :account_number
      t.string :reference_code
      t.datetime :transacted_at, precision: 0
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false # matched | needs_review | ignored | resolved
      t.string :review_reason        # unknown_code | wrong_amount | late | already_paid
      t.references :payment, foreign_key: true
      t.text :resolution_note
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at, precision: 0
      t.timestamps precision: 0

      t.index :sepay_id, unique: true # SePay retries: each transfer is handled once
      t.index :status
      t.check_constraint "direction IN ('in', 'out')", name: "bank_transactions_direction_valid"
      t.check_constraint "status IN ('matched', 'needs_review', 'ignored', 'resolved')", name: "bank_transactions_status_valid"
    end

    change_table :payments, bulk: true do |t|
      t.references :bank_transaction, foreign_key: true
    end

    change_table :bookings, bulk: true do |t|
      t.references :payment, foreign_key: true
      t.bigint :refund_vnd # owed to the customer when the venue cancels a paid booking (outage, broken court)
      t.datetime :refunded_at, precision: 0
      t.references :refunded_by, foreign_key: { to_table: :users }
      t.check_constraint "refund_vnd IS NULL OR refund_vnd > 0", name: "bookings_refund_positive"
      t.check_constraint "refunded_at IS NULL OR refund_vnd IS NOT NULL", name: "bookings_refunded_needs_amount"
    end

    # The account customers transfer to (shown on the QR code; not a secret).
    change_table :venues, bulk: true do |t|
      t.string :bank_code         # VietQR bank code or short name, e.g. MBBank, VCB
      t.string :bank_account_number
      t.string :bank_account_name
    end
  end
end
