class CreatePlaySessions < ActiveRecord::Migration[8.1]
  def change
    # Open play ("giao lưu", "vãng lai"): the venue keeps some courts for a few hours and sells places per player.
    create_table :play_sessions do |t|
      t.references :venue, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :title_en
      t.text :description
      t.bigint :court_ids, array: true, null: false
      t.datetime :starts_at, precision: 0, null: false
      t.datetime :ends_at, precision: 0, null: false
      t.integer :capacity, null: false
      t.bigint :price_vnd, null: false
      t.string :level
      t.string :status, null: false, default: "open"
      t.datetime :cancelled_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :play_sessions, "status IN ('open', 'cancelled')", name: "play_sessions_status_valid"
    add_check_constraint :play_sessions, "ends_at > starts_at", name: "play_sessions_range_valid"
    add_check_constraint :play_sessions, "capacity BETWEEN 1 AND 200", name: "play_sessions_capacity_valid"
    add_check_constraint :play_sessions, "price_vnd > 0 AND price_vnd % 1000 = 0", name: "play_sessions_price_valid"
    add_check_constraint :play_sessions, "cardinality(court_ids) >= 1", name: "play_sessions_courts_present"
    add_index :play_sessions, :starts_at

    # The courts it keeps are blocks (kind "block") pointing at it.
    add_reference :bookings, :play_session, foreign_key: true

    # Places a customer bought (quantity: themselves and friends), paid by transfer.
    create_table :play_session_tickets do |t|
      t.references :play_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :payment, foreign_key: true
      t.integer :quantity, null: false
      t.bigint :amount_vnd, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :checked_in_at, precision: 0
      t.datetime :cancelled_at, precision: 0
      t.bigint :refund_vnd
      t.datetime :refunded_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :play_session_tickets, "status IN ('pending', 'confirmed', 'cancelled')", name: "play_session_tickets_status_valid"
    add_check_constraint :play_session_tickets, "quantity BETWEEN 1 AND 10", name: "play_session_tickets_quantity_valid"
    add_reference :payments, :play_session_ticket, foreign_key: true
  end
end
