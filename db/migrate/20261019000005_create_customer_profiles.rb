# What the venue knows about a customer, by phone number (customers booked by phone may have no account):
# a private note, and the blacklist (no online booking).
class CreateCustomerProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_profiles do |t|
      t.string :phone, null: false
      t.text :note
      t.datetime :blocked_at, precision: 0
      t.string :blocked_reason
      t.references :blocked_by, foreign_key: { to_table: :users }
      t.timestamps precision: 0

      t.index :phone, unique: true
      t.check_constraint "phone ~ '^\\+84[0-9]{9}$'", name: "customer_profiles_phone_format"
      t.check_constraint "(blocked_at IS NULL) = (blocked_by_id IS NULL)", name: "customer_profiles_blocked_consistent"
    end
  end
end
