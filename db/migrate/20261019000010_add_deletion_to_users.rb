class AddDeletionToUsers < ActiveRecord::Migration[8.1]
  def change
    # Requested: signed out and locked at once; deleted (personal data removed) once nothing is pending.
    add_column :users, :deletion_requested_at, :datetime, precision: 0
    add_reference :users, :deletion_requested_by, foreign_key: { to_table: :users }
    add_column :users, :deleted_at, :datetime, precision: 0
    add_index :users, :deletion_requested_at, where: "deletion_requested_at IS NOT NULL AND deleted_at IS NULL"
  end
end
