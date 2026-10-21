class CreatePackages < ActiveRecord::Migration[8.1]
  def change
    # Prepaid hours the owner sells (e.g. 10 hours for less, to use within 60 days), optionally only at some times.
    create_table :packages do |t|
      t.references :venue, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_en
      t.integer :minutes, null: false
      t.bigint :price_vnd, null: false
      t.integer :valid_days, null: false
      t.integer :start_minute
      t.integer :end_minute
      t.boolean :active, null: false, default: true
      t.timestamps precision: 0
    end
    add_check_constraint :packages, "minutes > 0 AND minutes % 30 = 0", name: "packages_minutes_valid"
    add_check_constraint :packages, "price_vnd > 0 AND price_vnd % 1000 = 0", name: "packages_price_valid"
    add_check_constraint :packages, "valid_days BETWEEN 1 AND 730", name: "packages_valid_days_valid"
    add_check_constraint :packages, "(start_minute IS NULL) = (end_minute IS NULL) AND (start_minute IS NULL OR end_minute > start_minute)",
                         name: "packages_time_range_valid"

    # A customer's package: bought by transfer (payment), then hours taken off by bookings until expires_at.
    create_table :package_purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :package, null: false, foreign_key: true
      t.references :payment, foreign_key: true
      t.string :name, null: false
      t.integer :minutes_total, null: false
      t.integer :minutes_left, null: false
      t.bigint :price_vnd, null: false
      t.integer :valid_days, null: false
      t.integer :start_minute
      t.integer :end_minute
      t.string :status, null: false, default: "awaiting"
      t.datetime :paid_at, precision: 0
      t.datetime :expires_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :package_purchases, "status IN ('awaiting', 'active', 'cancelled')", name: "package_purchases_status_valid"
    add_check_constraint :package_purchases, "minutes_left >= 0 AND minutes_left <= minutes_total", name: "package_purchases_minutes_valid"
    add_check_constraint :package_purchases, "status <> 'active' OR (paid_at IS NOT NULL AND expires_at IS NOT NULL)", name: "package_purchases_active_paid"

    # A booking paid with prepaid hours: the package and how many minutes it took.
    add_reference :bookings, :package_purchase, foreign_key: true
    add_column :bookings, :package_minutes, :integer
    add_reference :payments, :package_purchase, foreign_key: true

    remove_check_constraint :payments, name: "payments_purpose_valid"
    add_check_constraint :payments, "purpose IN ('bookings', 'series_period', 'package', 'tickets')", name: "payments_purpose_valid"
  end
end
