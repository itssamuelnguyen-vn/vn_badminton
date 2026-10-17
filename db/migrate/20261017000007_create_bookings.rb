# The most important table. Two kinds of records share it:
#   - reservation : a customer booking
#   - block       : court unavailable (maintenance, holiday, private event)
# Sharing one table lets ONE exclusion constraint prevent every overlap,
# including a customer booking a court that is under maintenance.
#
# Times are timestamptz (UTC) and always sit on the 30-minute grid.
# Overlap uses half-open ranges [starts_at, ends_at):
#   18:00-19:00 and 19:00-20:00 do NOT overlap.
class CreateBookings < ActiveRecord::Migration[8.1]
  ACTIVE_STATUSES_SQL = "status IN ('pending', 'confirmed', 'checked_in', 'completed', 'no_show')"

  def change
    create_table :bookings do |t|
      t.references :court,        null: false, foreign_key: true, index: false
      t.references :user,         foreign_key: true                          # customer account (NULL for walk-in customers)
      t.references :created_by,   foreign_key: { to_table: :users }          # staff member who created it on the customer's behalf
      t.references :cancelled_by, foreign_key: { to_table: :users }, index: false

      t.string :code, null: false # lookup code for customers, e.g. K7Q2M9XA
      t.string :kind, null: false, default: "reservation"

      t.datetime :starts_at, null: false
      t.datetime :ends_at,   null: false

      t.string   :status, null: false, default: "confirmed"
      t.datetime :expires_at # hold expiry when status = pending (for online payments later)

      t.string :source, null: false, default: "online"

      # Snapshot of customer details at booking time (walk-in customers have no account).
      t.string :customer_name
      t.string :customer_phone

      # Snapshot of the price at booking time; later price changes do not affect existing bookings.
      t.bigint :total_amount_vnd, null: false, default: 0
      t.jsonb  :price_breakdown,  null: false, default: []

      t.string   :payment_status, null: false, default: "unpaid"
      t.datetime :paid_at

      t.datetime :checked_in_at
      t.datetime :cancelled_at
      t.string   :cancellation_reason

      t.text    :note
      t.integer :lock_version, null: false, default: 0 # optimistic locking: two people editing at once

      t.timestamps
    end

    add_index :bookings, :code, unique: true
    add_index :bookings, [ :court_id, :starts_at ]
    add_index :bookings, :starts_at
    add_index :bookings, :expires_at, where: "status = 'pending'"

    # ---- NO DOUBLE BOOKING ----
    # Two active bookings on the same court must not overlap in time.
    # Cancelled bookings are excluded, so their slot can be booked again.
    add_exclusion_constraint :bookings,
      "court_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&",
      using: :gist,
      where: ACTIVE_STATUSES_SQL,
      name: "bookings_no_overlap"

    # ---- Allowed values ----
    add_check_constraint :bookings, "kind IN ('reservation', 'block')", name: "bookings_kind_valid"
    add_check_constraint :bookings,
      "status IN ('pending', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show')",
      name: "bookings_status_valid"
    add_check_constraint :bookings, "source IN ('online', 'phone', 'walk_in', 'staff')", name: "bookings_source_valid"
    add_check_constraint :bookings, "payment_status IN ('unpaid', 'paid', 'refunded')", name: "bookings_payment_status_valid"
    add_check_constraint :bookings, "code ~ '^[A-Z0-9]{8}$'", name: "bookings_code_format"

    # ---- Time ----
    add_check_constraint :bookings, "ends_at > starts_at", name: "bookings_ends_after_starts"
    add_check_constraint :bookings, "ends_at - starts_at <= interval '24 hours'", name: "bookings_max_duration"
    add_check_constraint :bookings,
      "mod(extract(epoch FROM starts_at), 1800) = 0 AND mod(extract(epoch FROM ends_at), 1800) = 0",
      name: "bookings_aligned_to_slot"

    # ---- Rules per kind ----
    add_check_constraint :bookings, <<~SQL.squish, name: "bookings_kind_fields"
      (kind = 'reservation'
        AND customer_name IS NOT NULL AND length(btrim(customer_name)) > 0
        AND customer_phone IS NOT NULL)
      OR
      (kind = 'block'
        AND user_id IS NULL AND customer_name IS NULL AND customer_phone IS NULL
        AND total_amount_vnd = 0 AND payment_status = 'unpaid' AND source = 'staff')
    SQL
    add_check_constraint :bookings, %q(customer_phone ~ '^\+84[0-9]{9}$'), name: "bookings_customer_phone_format"
    add_check_constraint :bookings, "source <> 'online' OR user_id IS NOT NULL", name: "bookings_online_requires_user"

    # ---- Money ----
    add_check_constraint :bookings, "total_amount_vnd >= 0", name: "bookings_amount_non_negative"
    add_check_constraint :bookings, "jsonb_typeof(price_breakdown) = 'array'", name: "bookings_price_breakdown_array"
    add_check_constraint :bookings, "(payment_status = 'unpaid') = (paid_at IS NULL)", name: "bookings_paid_at_consistent"

    # ---- Status must come with its matching data ----
    add_check_constraint :bookings, "(status = 'cancelled') = (cancelled_at IS NOT NULL)", name: "bookings_cancelled_at_consistent"
    add_check_constraint :bookings, "status <> 'pending' OR expires_at IS NOT NULL", name: "bookings_pending_requires_expiry"
    add_check_constraint :bookings,
      "status NOT IN ('checked_in', 'completed') OR checked_in_at IS NOT NULL",
      name: "bookings_checked_in_at_present"
  end
end
