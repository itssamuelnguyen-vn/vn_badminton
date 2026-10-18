# Staff accounts: run the day-to-day (board, bookings, customers) without seeing money or settings.
class AddStaffRole < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :users, "role IN ('customer', 'admin')", name: "users_role_valid"
    add_check_constraint :users, "role IN ('customer', 'staff', 'admin')", name: "users_role_valid"
  end
end
