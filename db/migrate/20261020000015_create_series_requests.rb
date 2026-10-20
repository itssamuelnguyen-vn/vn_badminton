class CreateSeriesRequests < ActiveRecord::Migration[8.1]
  def change
    # A customer asking for a weekly booking from the app; the staff turn it into a BookingSeries (or decline it).
    create_table :series_requests do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :court_ids, array: true, null: false
      t.integer :days_of_week, limit: 2, array: true, null: false
      t.integer :start_minute, null: false
      t.integer :end_minute, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.text :note
      t.string :status, null: false, default: "pending"
      t.references :series, foreign_key: { to_table: :booking_series }
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at, precision: 0
      t.string :decline_reason
      t.timestamps precision: 0
    end
    add_check_constraint :series_requests, "status IN ('pending', 'approved', 'declined', 'cancelled')", name: "series_requests_status_valid"
    add_check_constraint :series_requests, "cardinality(court_ids) >= 1", name: "series_requests_courts_present"
    add_check_constraint :series_requests, "start_minute >= 0 AND end_minute <= 1440 AND end_minute > start_minute AND start_minute % 30 = 0 AND end_minute % 30 = 0",
                         name: "series_requests_time_range_valid"
    add_check_constraint :series_requests, "ends_on >= starts_on", name: "series_requests_date_range_valid"
  end
end
