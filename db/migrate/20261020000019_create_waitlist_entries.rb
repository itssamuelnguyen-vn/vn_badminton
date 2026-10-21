class CreateWaitlistEntries < ActiveRecord::Migration[8.1]
  def change
    # "Tell me when it frees up": a customer waiting for a time range (any court) that is taken.
    create_table :waitlist_entries do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :starts_at, precision: 0, null: false
      t.datetime :ends_at, precision: 0, null: false
      t.datetime :notified_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :waitlist_entries, "ends_at > starts_at", name: "waitlist_entries_range_valid"
    add_index :waitlist_entries, :starts_at, where: "notified_at IS NULL"
  end
end
