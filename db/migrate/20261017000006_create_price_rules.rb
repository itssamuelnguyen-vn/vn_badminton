# Time-based pricing. The price of each 30-minute slot is picked in this order:
#   1. court-specific rules (court_id) before venue-wide rules (court_id NULL)
#   2. higher priority
#   3. higher id (the most recently created rule)
# A slot that matches no rule cannot be booked.
#
# VND has no minor unit, so amounts are stored as bigint, never decimal/float.
class CreatePriceRules < ActiveRecord::Migration[8.1]
  def change
    create_table :price_rules do |t|
      t.references :venue, null: false, foreign_key: true
      t.bigint  :court_id # NULL = applies to every court in the venue
      t.string  :name, null: false
      t.integer :days_of_week, array: true, null: false, limit: 2 # smallint[], 0 = Sunday
      t.integer :start_minute, null: false
      t.integer :end_minute,   null: false
      t.bigint  :price_per_hour_vnd, null: false
      t.integer :priority, null: false, default: 0
      t.date    :valid_from
      t.date    :valid_until
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :price_rules, :court_id
    # Composite FK: court_id must be a court of this venue_id. Skipped when court_id is NULL (MATCH SIMPLE).
    add_foreign_key :price_rules, :courts, column: [ :court_id, :venue_id ], primary_key: [ :id, :venue_id ],
                                           name: "fk_price_rules_court_venue"

    add_check_constraint :price_rules, "length(btrim(name)) > 0", name: "price_rules_name_present"
    add_check_constraint :price_rules,
      "cardinality(days_of_week) BETWEEN 1 AND 7 AND days_of_week <@ ARRAY[0,1,2,3,4,5,6]::smallint[]",
      name: "price_rules_days_valid"
    add_check_constraint :price_rules,
      "start_minute >= 0 AND end_minute <= 1440 AND end_minute > start_minute AND start_minute % 30 = 0 AND end_minute % 30 = 0",
      name: "price_rules_time_range_valid"
    # Multiples of 1,000 VND so every 30-minute slot price is a whole number (a multiple of 500 VND).
    add_check_constraint :price_rules,
      "price_per_hour_vnd > 0 AND price_per_hour_vnd <= 100000000 AND price_per_hour_vnd % 1000 = 0",
      name: "price_rules_price_valid"
    add_check_constraint :price_rules,
      "valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from",
      name: "price_rules_validity_range"
  end
end
