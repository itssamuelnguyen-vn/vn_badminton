# Limits on what one customer can hold online: a number of upcoming bookings, and a temporary lock
# on online booking after too many cancellations in one day. Bookings are now up to 4 hours long.
class AddBookingLimits < ActiveRecord::Migration[8.1]
  def change
    change_table :venues, bulk: true do |t|
      t.integer :max_upcoming_bookings, null: false, default: 2
      t.integer :cancellation_lock_threshold, null: false, default: 3
      t.integer :cancellation_lock_days, null: false, default: 7
      t.check_constraint "max_upcoming_bookings BETWEEN 1 AND 50", name: "venues_max_upcoming_bookings_valid"
      t.check_constraint "cancellation_lock_threshold BETWEEN 1 AND 20", name: "venues_cancellation_lock_threshold_valid"
      t.check_constraint "cancellation_lock_days BETWEEN 1 AND 90", name: "venues_cancellation_lock_days_valid"
    end
    change_column_default :venues, :max_booking_minutes, from: 180, to: 240
    up_only { execute "UPDATE venues SET max_booking_minutes = 240 WHERE max_booking_minutes = 180" }

    add_column :users, :booking_locked_until, :datetime, precision: 0
  end
end
