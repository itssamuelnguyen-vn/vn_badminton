# A reservation of a deleted account keeps its court, time and amount but loses the customer's phone
# (Accounts::Deletion). New reservations still need one: Booking validates it.
class AllowAnonymizedReservations < ActiveRecord::Migration[8.1]
  OLD = "kind::text = 'reservation'::text AND customer_name IS NOT NULL AND length(btrim(customer_name::text)) > 0 AND customer_phone IS NOT NULL " \
        "OR kind::text = 'block'::text AND user_id IS NULL AND customer_name IS NULL AND customer_phone IS NULL AND total_amount_vnd = 0 " \
        "AND payment_status::text = 'unpaid'::text AND source::text = 'staff'::text"
  NEW = "kind::text = 'reservation'::text AND customer_name IS NOT NULL AND length(btrim(customer_name::text)) > 0 " \
        "OR kind::text = 'block'::text AND user_id IS NULL AND customer_name IS NULL AND customer_phone IS NULL AND total_amount_vnd = 0 " \
        "AND payment_status::text = 'unpaid'::text AND source::text = 'staff'::text"

  def up
    remove_check_constraint :bookings, name: "bookings_kind_fields"
    add_check_constraint :bookings, NEW, name: "bookings_kind_fields"
  end

  def down
    remove_check_constraint :bookings, name: "bookings_kind_fields"
    add_check_constraint :bookings, OLD, name: "bookings_kind_fields"
  end
end
