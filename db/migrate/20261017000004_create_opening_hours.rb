# Opening hours per day of week. No row for a day means the venue is closed that day.
#
# Stored as MINUTES since midnight (integer) instead of a time column:
#   - Rails attaches the date 2000-01-01 to time columns and they shift easily across time zones
#   - can represent 24:00 (1440) for venues open until midnight
# Examples: 05:30 -> 330, 22:00 -> 1320.
class CreateOpeningHours < ActiveRecord::Migration[8.1]
  def change
    create_table :opening_hours do |t|
      t.references :venue, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :day_of_week,   null: false, limit: 2 # 0 = Sunday ... 6 = Saturday (same as Ruby Date#wday)
      t.integer :opens_minute,  null: false
      t.integer :closes_minute, null: false

      t.timestamps
    end

    add_index :opening_hours, [ :venue_id, :day_of_week ], unique: true

    add_check_constraint :opening_hours, "day_of_week BETWEEN 0 AND 6", name: "opening_hours_day_valid"
    add_check_constraint :opening_hours,
      "opens_minute >= 0 AND closes_minute <= 1440 AND closes_minute > opens_minute",
      name: "opening_hours_range_valid"
    add_check_constraint :opening_hours,
      "opens_minute % 30 = 0 AND closes_minute % 30 = 0",
      name: "opening_hours_aligned_to_slot"
  end
end
