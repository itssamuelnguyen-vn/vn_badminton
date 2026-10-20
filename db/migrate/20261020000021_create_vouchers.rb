class CreateVouchers < ActiveRecord::Migration[8.1]
  def change
    # Discount codes the owner gives out (Voucher): a percentage or an amount off the court price of online bookings.
    create_table :vouchers do |t|
      t.references :venue, null: false, foreign_key: true
      t.string :code, null: false, index: { unique: true }
      t.string :description
      t.string :kind, null: false
      t.integer :value, null: false
      t.bigint :max_discount_vnd
      t.bigint :min_amount_vnd, null: false, default: 0
      t.date :valid_from, null: false
      t.date :valid_until, null: false
      t.integer :days_of_week, limit: 2, array: true
      t.integer :start_minute
      t.integer :end_minute
      t.integer :usage_limit
      t.integer :per_user_limit, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.timestamps precision: 0
    end
    add_check_constraint :vouchers, "kind IN ('percent', 'amount')", name: "vouchers_kind_valid"
    add_check_constraint :vouchers, "value > 0 AND (kind <> 'percent' OR value <= 100)", name: "vouchers_value_valid"
    add_check_constraint :vouchers, "valid_until >= valid_from", name: "vouchers_date_range_valid"
    add_check_constraint :vouchers, "(start_minute IS NULL) = (end_minute IS NULL) AND (start_minute IS NULL OR end_minute > start_minute)",
                         name: "vouchers_time_range_valid"

    # Who used a code, on which payment and for how much. Counts while the payment is awaiting or paid.
    create_table :voucher_redemptions do |t|
      t.references :voucher, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :payment, null: false, foreign_key: true, index: { unique: true }
      t.bigint :discount_vnd, null: false
      t.timestamps precision: 0
    end

    # The discount on the court price of a booking (member tier, voucher or prepaid hours) and on its payment.
    add_column :bookings, :discount_vnd, :bigint, null: false, default: 0
    add_check_constraint :bookings, "discount_vnd >= 0 AND discount_vnd <= total_amount_vnd", name: "bookings_discount_valid"
    add_column :payments, :discount_vnd, :bigint, null: false, default: 0
    # "tier" or "voucher": which offer the discount came from (the better one for the customer).
    add_column :payments, :offer, :string
  end
end
