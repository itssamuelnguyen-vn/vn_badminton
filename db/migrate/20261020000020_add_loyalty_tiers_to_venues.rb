class AddLoyaltyTiersToVenues < ActiveRecord::Migration[8.1]
  def change
    # Member tiers by hours played in the last 12 months (Loyalty::Tier): silver, gold and diamond (bronze below),
    # each with its discount on online bookings.
    change_table :venues, bulk: true do |t|
      t.boolean :loyalty_enabled, null: false, default: true
      t.integer :silver_hours, null: false, default: 20
      t.integer :silver_percent, null: false, default: 3
      t.integer :gold_hours, null: false, default: 60
      t.integer :gold_percent, null: false, default: 5
      t.integer :diamond_hours, null: false, default: 150
      t.integer :diamond_percent, null: false, default: 10
    end
    add_check_constraint :venues, "silver_hours > 0 AND gold_hours > silver_hours AND diamond_hours > gold_hours", name: "venues_tier_hours_ascending"
    add_check_constraint :venues, "silver_percent BETWEEN 0 AND 50 AND gold_percent BETWEEN 0 AND 50 AND diamond_percent BETWEEN 0 AND 50",
                         name: "venues_tier_percents_valid"
  end
end
