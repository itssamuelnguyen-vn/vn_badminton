# Courts within a venue. Never delete a court with booking history; set status to inactive instead.
# Maintenance and holidays are stored as bookings of kind "block" (see the bookings table).
class CreateCourts < ActiveRecord::Migration[8.1]
  def change
    create_table :courts do |t|
      t.references :venue, null: false, foreign_key: true, index: false
      t.string  :name,     null: false
      t.integer :position, null: false, default: 0
      t.string  :status,   null: false, default: "active"

      t.timestamps
    end

    # Court names are unique within a venue, case-insensitively.
    add_index :courts, "venue_id, lower(name)", unique: true, name: "index_courts_on_venue_id_and_lower_name"
    # Target of the composite foreign key (court_id, venue_id) from price_rules,
    # guaranteeing that a court-specific price rule belongs to that court's venue.
    add_index :courts, [ :id, :venue_id ], unique: true

    add_check_constraint :courts, "length(btrim(name)) BETWEEN 1 AND 50", name: "courts_name_length"
    add_check_constraint :courts, "status IN ('active', 'inactive')", name: "courts_status_valid"
  end
end
