# A venue is one location with several courts.
# Booking rules live here so they can be configured without a deploy.
# All durations are multiples of 30 minutes (a fixed, system-wide slot grid).
class CreateVenues < ActiveRecord::Migration[8.1]
  def change
    create_table :venues do |t|
      t.string  :name,      null: false
      t.string  :slug,      null: false
      t.string  :address,   null: false
      t.string  :phone
      t.string  :time_zone, null: false, default: "Asia/Ho_Chi_Minh"

      t.integer :min_booking_minutes,       null: false, default: 60
      t.integer :max_booking_minutes,       null: false, default: 180
      t.integer :cancellation_cutoff_hours, null: false, default: 2
      t.integer :booking_horizon_days,      null: false, default: 14

      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :venues, :slug, unique: true

    add_check_constraint :venues, "length(btrim(name)) > 0", name: "venues_name_present"
    add_check_constraint :venues, "length(btrim(address)) > 0", name: "venues_address_present"
    add_check_constraint :venues, "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'", name: "venues_slug_format"
    add_check_constraint :venues, %q(phone ~ '^\+84[0-9]{9}$'), name: "venues_phone_format"
    add_check_constraint :venues, "status IN ('active', 'inactive')", name: "venues_status_valid"
    add_check_constraint :venues,
      "min_booking_minutes >= 30 AND min_booking_minutes % 30 = 0",
      name: "venues_min_booking_minutes_valid"
    add_check_constraint :venues,
      "max_booking_minutes >= min_booking_minutes AND max_booking_minutes <= 720 AND max_booking_minutes % 30 = 0",
      name: "venues_max_booking_minutes_valid"
    add_check_constraint :venues, "cancellation_cutoff_hours BETWEEN 0 AND 168", name: "venues_cancellation_cutoff_valid"
    add_check_constraint :venues, "booking_horizon_days BETWEEN 1 AND 365", name: "venues_booking_horizon_valid"
  end
end
