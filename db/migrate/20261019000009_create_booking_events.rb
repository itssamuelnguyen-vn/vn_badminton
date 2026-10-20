class CreateBookingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_events do |t|
      # Deleted with the booking: only holds of the confirmation page are ever deleted.
      t.references :booking, null: false, foreign_key: { on_delete: :cascade }
      # Who did it; null for the system (bank transfer webhook, background jobs).
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, precision: 0, null: false
    end
    add_index :booking_events, [ :booking_id, :id ]
  end
end
