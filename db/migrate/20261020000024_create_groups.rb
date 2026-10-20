class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    # Customers who play together: joined with an invite code, they see the bookings members share with the
    # group and each player's share of the price (the app does not collect it).
    create_table :groups do |t|
      t.string :name, null: false
      t.string :invite_code, null: false, index: { unique: true }
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.timestamps precision: 0
    end

    create_table :group_memberships do |t|
      t.references :group, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps precision: 0
    end
    add_index :group_memberships, %i[group_id user_id], unique: true

    create_table :group_shares do |t|
      t.references :group, null: false, foreign_key: { on_delete: :cascade }
      t.references :booking, null: false, foreign_key: { on_delete: :cascade }
      t.references :shared_by, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.integer :players, null: false
      t.timestamps precision: 0
    end
    add_index :group_shares, %i[group_id booking_id], unique: true
    add_check_constraint :group_shares, "players BETWEEN 1 AND 50", name: "group_shares_players_valid"
  end
end
