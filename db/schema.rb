# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_19_000009) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "bank_transactions", force: :cascade do |t|
    t.bigint "sepay_id", null: false
    t.string "direction", null: false
    t.bigint "amount_vnd", null: false
    t.text "content"
    t.string "gateway"
    t.string "account_number"
    t.string "reference_code"
    t.datetime "transacted_at", precision: 0
    t.jsonb "payload", default: {}, null: false
    t.string "status", null: false
    t.string "review_reason"
    t.bigint "payment_id"
    t.text "resolution_note"
    t.bigint "resolved_by_id"
    t.datetime "resolved_at", precision: 0
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.index ["payment_id"], name: "index_bank_transactions_on_payment_id"
    t.index ["resolved_by_id"], name: "index_bank_transactions_on_resolved_by_id"
    t.index ["sepay_id"], name: "index_bank_transactions_on_sepay_id", unique: true
    t.index ["status"], name: "index_bank_transactions_on_status"
    t.check_constraint "direction::text = ANY (ARRAY['in'::character varying, 'out'::character varying]::text[])", name: "bank_transactions_direction_valid"
    t.check_constraint "status::text = ANY (ARRAY['matched'::character varying, 'needs_review'::character varying, 'ignored'::character varying, 'resolved'::character varying]::text[])", name: "bank_transactions_status_valid"
  end

  create_table "booking_events", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "actor_id"
    t.string "action", null: false
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", precision: 0, null: false
    t.index ["actor_id"], name: "index_booking_events_on_actor_id"
    t.index ["booking_id", "id"], name: "index_booking_events_on_booking_id_and_id"
    t.index ["booking_id"], name: "index_booking_events_on_booking_id"
  end

  create_table "booking_series", force: :cascade do |t|
    t.string "customer_name", null: false
    t.string "customer_phone", null: false
    t.bigint "user_id"
    t.bigint "created_by_id", null: false
    t.bigint "court_ids", null: false, array: true
    t.integer "days_of_week", limit: 2, null: false, array: true
    t.integer "start_minute", null: false
    t.integer "end_minute", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.bigint "price_per_hour_vnd"
    t.text "note"
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.index ["created_by_id"], name: "index_booking_series_on_created_by_id"
    t.index ["user_id"], name: "index_booking_series_on_user_id"
    t.check_constraint "cardinality(court_ids) >= 1", name: "booking_series_courts_present"
    t.check_constraint "cardinality(days_of_week) >= 1 AND cardinality(days_of_week) <= 7 AND days_of_week <@ ARRAY[0::smallint, 1::smallint, 2::smallint, 3::smallint, 4::smallint, 5::smallint, 6::smallint]", name: "booking_series_days_valid"
    t.check_constraint "customer_phone::text ~ '^\\+84[0-9]{9}$'::text", name: "booking_series_customer_phone_format"
    t.check_constraint "ends_on >= starts_on", name: "booking_series_date_range_valid"
    t.check_constraint "length(btrim(customer_name::text)) > 0", name: "booking_series_customer_name_present"
    t.check_constraint "price_per_hour_vnd IS NULL OR price_per_hour_vnd > 0 AND (price_per_hour_vnd % 1000::bigint) = 0", name: "booking_series_price_valid"
    t.check_constraint "start_minute >= 0 AND end_minute <= 1440 AND end_minute > start_minute AND (start_minute % 30) = 0 AND (end_minute % 30) = 0", name: "booking_series_time_range_valid"
  end

  create_table "booking_series_periods", force: :cascade do |t|
    t.bigint "series_id", null: false
    t.date "month", null: false
    t.bigint "amount_vnd", null: false
    t.bigint "credit_vnd", default: 0, null: false
    t.datetime "paid_at", precision: 0, null: false
    t.bigint "paid_by_id", null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.index ["paid_by_id"], name: "index_booking_series_periods_on_paid_by_id"
    t.index ["series_id", "month"], name: "index_booking_series_periods_on_series_id_and_month", unique: true
    t.index ["series_id"], name: "index_booking_series_periods_on_series_id"
    t.check_constraint "EXTRACT(day FROM month) = 1::numeric", name: "booking_series_periods_month_start"
    t.check_constraint "amount_vnd >= 0 AND credit_vnd >= 0 AND credit_vnd <= amount_vnd", name: "booking_series_periods_amounts_valid"
  end

  create_table "bookings", force: :cascade do |t|
    t.bigint "court_id", null: false
    t.bigint "user_id"
    t.bigint "created_by_id"
    t.bigint "cancelled_by_id"
    t.string "code", null: false
    t.string "kind", default: "reservation", null: false
    t.datetime "starts_at", precision: 0, null: false
    t.datetime "ends_at", precision: 0, null: false
    t.string "status", default: "confirmed", null: false
    t.datetime "expires_at", precision: 0
    t.string "source", default: "online", null: false
    t.string "customer_name"
    t.string "customer_phone"
    t.bigint "total_amount_vnd", default: 0, null: false
    t.jsonb "price_breakdown", default: [], null: false
    t.string "payment_status", default: "unpaid", null: false
    t.datetime "paid_at", precision: 0
    t.datetime "checked_in_at", precision: 0
    t.datetime "cancelled_at", precision: 0
    t.string "cancellation_reason"
    t.text "note"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.datetime "reminder_sent_at", precision: 0
    t.bigint "series_id"
    t.bigint "series_refund_vnd"
    t.bigint "series_refund_period_id"
    t.bigint "payment_id"
    t.bigint "refund_vnd"
    t.datetime "refunded_at", precision: 0
    t.bigint "refunded_by_id"
    t.index ["code"], name: "index_bookings_on_code", unique: true
    t.index ["court_id", "starts_at"], name: "index_bookings_on_court_id_and_starts_at"
    t.index ["created_by_id"], name: "index_bookings_on_created_by_id"
    t.index ["expires_at"], name: "index_bookings_on_expires_at", where: "((status)::text = 'pending'::text)"
    t.index ["payment_id"], name: "index_bookings_on_payment_id"
    t.index ["refunded_by_id"], name: "index_bookings_on_refunded_by_id"
    t.index ["series_id"], name: "index_bookings_on_series_id"
    t.index ["series_refund_period_id"], name: "index_bookings_on_series_refund_period_id"
    t.index ["starts_at"], name: "index_bookings_on_starts_at"
    t.index ["user_id"], name: "index_bookings_on_user_id"
    t.check_constraint "(ends_at - starts_at) <= 'PT24H'::interval", name: "bookings_max_duration"
    t.check_constraint "(payment_status::text = 'unpaid'::text) = (paid_at IS NULL)", name: "bookings_paid_at_consistent"
    t.check_constraint "(status::text <> ALL (ARRAY['checked_in'::character varying::text, 'completed'::character varying::text])) OR checked_in_at IS NOT NULL", name: "bookings_checked_in_at_present"
    t.check_constraint "(status::text = 'cancelled'::text) = (cancelled_at IS NOT NULL)", name: "bookings_cancelled_at_consistent"
    t.check_constraint "code::text ~ '^[A-Z0-9]{8}$'::text", name: "bookings_code_format"
    t.check_constraint "customer_phone::text ~ '^\\+84[0-9]{9}$'::text", name: "bookings_customer_phone_format"
    t.check_constraint "ends_at > starts_at", name: "bookings_ends_after_starts"
    t.check_constraint "jsonb_typeof(price_breakdown) = 'array'::text", name: "bookings_price_breakdown_array"
    t.check_constraint "kind::text = 'reservation'::text AND customer_name IS NOT NULL AND length(btrim(customer_name::text)) > 0 AND customer_phone IS NOT NULL OR kind::text = 'block'::text AND user_id IS NULL AND customer_name IS NULL AND customer_phone IS NULL AND total_amount_vnd = 0 AND payment_status::text = 'unpaid'::text AND source::text = 'staff'::text", name: "bookings_kind_fields"
    t.check_constraint "kind::text = ANY (ARRAY['reservation'::character varying, 'block'::character varying]::text[])", name: "bookings_kind_valid"
    t.check_constraint "mod(EXTRACT(epoch FROM starts_at), 1800::numeric) = 0::numeric AND mod(EXTRACT(epoch FROM ends_at), 1800::numeric) = 0::numeric", name: "bookings_aligned_to_slot"
    t.check_constraint "payment_status::text = ANY (ARRAY['unpaid'::character varying, 'paid'::character varying, 'refunded'::character varying]::text[])", name: "bookings_payment_status_valid"
    t.check_constraint "refund_vnd IS NULL OR refund_vnd > 0", name: "bookings_refund_positive"
    t.check_constraint "refunded_at IS NULL OR refund_vnd IS NOT NULL", name: "bookings_refunded_needs_amount"
    t.check_constraint "series_id IS NULL OR kind::text = 'reservation'::text", name: "bookings_series_reservations_only"
    t.check_constraint "series_refund_vnd IS NULL OR series_refund_vnd >= 0 AND series_id IS NOT NULL", name: "bookings_series_refund_valid"
    t.check_constraint "source::text <> 'online'::text OR user_id IS NOT NULL", name: "bookings_online_requires_user"
    t.check_constraint "source::text = ANY (ARRAY['online'::character varying, 'phone'::character varying, 'walk_in'::character varying, 'staff'::character varying]::text[])", name: "bookings_source_valid"
    t.check_constraint "status::text <> 'pending'::text OR expires_at IS NOT NULL", name: "bookings_pending_requires_expiry"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'checked_in'::character varying, 'completed'::character varying, 'cancelled'::character varying, 'no_show'::character varying]::text[])", name: "bookings_status_valid"
    t.check_constraint "total_amount_vnd >= 0", name: "bookings_amount_non_negative"
    t.exclusion_constraint "court_id WITH =, tstzrange(starts_at, ends_at, '[)'::text) WITH &&", where: "(status)::text = ANY (ARRAY[('pending'::character varying)::text, ('confirmed'::character varying)::text, ('checked_in'::character varying)::text, ('completed'::character varying)::text, ('no_show'::character varying)::text])", using: :gist, name: "bookings_no_overlap"
  end

  create_table "courts", force: :cascade do |t|
    t.bigint "venue_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.index "venue_id, lower((name)::text)", name: "index_courts_on_venue_id_and_lower_name", unique: true
    t.index ["id", "venue_id"], name: "index_courts_on_id_and_venue_id", unique: true
    t.check_constraint "length(btrim(name::text)) >= 1 AND length(btrim(name::text)) <= 50", name: "courts_name_length"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])", name: "courts_status_valid"
  end

  create_table "customer_profiles", force: :cascade do |t|
    t.string "phone", null: false
    t.text "note"
    t.datetime "blocked_at", precision: 0
    t.string "blocked_reason"
    t.bigint "blocked_by_id"
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.index ["blocked_by_id"], name: "index_customer_profiles_on_blocked_by_id"
    t.index ["phone"], name: "index_customer_profiles_on_phone", unique: true
    t.check_constraint "(blocked_at IS NULL) = (blocked_by_id IS NULL)", name: "customer_profiles_blocked_consistent"
    t.check_constraint "phone::text ~ '^\\+84[0-9]{9}$'::text", name: "customer_profiles_phone_format"
  end

  create_table "opening_hours", force: :cascade do |t|
    t.bigint "venue_id", null: false
    t.integer "day_of_week", limit: 2, null: false
    t.integer "opens_minute", null: false
    t.integer "closes_minute", null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.index ["venue_id", "day_of_week"], name: "index_opening_hours_on_venue_id_and_day_of_week", unique: true
    t.check_constraint "(opens_minute % 30) = 0 AND (closes_minute % 30) = 0", name: "opening_hours_aligned_to_slot"
    t.check_constraint "day_of_week >= 0 AND day_of_week <= 6", name: "opening_hours_day_valid"
    t.check_constraint "opens_minute >= 0 AND closes_minute <= 1440 AND closes_minute > opens_minute", name: "opening_hours_range_valid"
  end

  create_table "payments", force: :cascade do |t|
    t.string "code", null: false
    t.string "token", null: false
    t.string "purpose", null: false
    t.string "status", default: "awaiting", null: false
    t.bigint "amount_vnd", null: false
    t.datetime "expires_at", precision: 0
    t.datetime "paid_at", precision: 0
    t.bigint "user_id"
    t.bigint "created_by_id"
    t.bigint "series_id"
    t.date "series_month"
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.bigint "bank_transaction_id"
    t.index ["bank_transaction_id"], name: "index_payments_on_bank_transaction_id"
    t.index ["code"], name: "index_payments_on_code", unique: true
    t.index ["created_by_id"], name: "index_payments_on_created_by_id"
    t.index ["series_id"], name: "index_payments_on_series_id"
    t.index ["token"], name: "index_payments_on_token", unique: true
    t.index ["user_id"], name: "index_payments_on_user_id"
    t.check_constraint "(status::text = 'paid'::text) = (paid_at IS NOT NULL)", name: "payments_paid_at_consistent"
    t.check_constraint "amount_vnd > 0", name: "payments_amount_positive"
    t.check_constraint "code::text ~ '^VNB[A-Z0-9]{8}$'::text", name: "payments_code_format"
    t.check_constraint "purpose::text <> 'bookings'::text OR expires_at IS NOT NULL", name: "payments_bookings_expiry"
    t.check_constraint "purpose::text <> 'series_period'::text OR series_id IS NOT NULL AND series_month IS NOT NULL", name: "payments_series_period_target"
    t.check_constraint "purpose::text = ANY (ARRAY['bookings'::character varying, 'series_period'::character varying]::text[])", name: "payments_purpose_valid"
    t.check_constraint "status::text = ANY (ARRAY['awaiting'::character varying, 'paid'::character varying, 'expired'::character varying, 'cancelled'::character varying]::text[])", name: "payments_status_valid"
  end

  create_table "price_rules", force: :cascade do |t|
    t.bigint "venue_id", null: false
    t.bigint "court_id"
    t.string "name", null: false
    t.integer "days_of_week", limit: 2, null: false, array: true
    t.integer "start_minute", null: false
    t.integer "end_minute", null: false
    t.bigint "price_per_hour_vnd", null: false
    t.integer "priority", default: 0, null: false
    t.date "valid_from"
    t.date "valid_until"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.string "name_en"
    t.index ["court_id"], name: "index_price_rules_on_court_id"
    t.index ["venue_id"], name: "index_price_rules_on_venue_id"
    t.check_constraint "cardinality(days_of_week) >= 1 AND cardinality(days_of_week) <= 7 AND days_of_week <@ ARRAY[0::smallint, 1::smallint, 2::smallint, 3::smallint, 4::smallint, 5::smallint, 6::smallint]", name: "price_rules_days_valid"
    t.check_constraint "length(btrim(name::text)) > 0", name: "price_rules_name_present"
    t.check_constraint "name_en IS NULL OR length(btrim(name_en::text)) > 0", name: "price_rules_name_en_present"
    t.check_constraint "price_per_hour_vnd > 0 AND price_per_hour_vnd <= 100000000 AND (price_per_hour_vnd % 1000::bigint) = 0", name: "price_rules_price_valid"
    t.check_constraint "start_minute >= 0 AND end_minute <= 1440 AND end_minute > start_minute AND (start_minute % 30) = 0 AND (end_minute % 30) = 0", name: "price_rules_time_range_valid"
    t.check_constraint "valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from", name: "price_rules_validity_range"
  end

  create_table "users", force: :cascade do |t|
    t.citext "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: 0
    t.datetime "remember_created_at", precision: 0
    t.string "full_name", null: false
    t.string "phone"
    t.string "role", default: "customer", null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.string "locale", default: "vi", null: false
    t.datetime "booking_locked_until", precision: 0
    t.datetime "privacy_accepted_at", precision: 0
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: 0
    t.datetime "confirmation_sent_at", precision: 0
    t.string "unconfirmed_email"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["phone"], name: "index_users_on_phone", unique: true, where: "(phone IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.check_constraint "email ~ '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$'::citext", name: "users_email_format"
    t.check_constraint "length(btrim(full_name::text)) >= 1 AND length(btrim(full_name::text)) <= 100", name: "users_full_name_length"
    t.check_constraint "locale::text = ANY (ARRAY['vi'::character varying, 'en'::character varying]::text[])", name: "users_locale_valid"
    t.check_constraint "phone::text ~ '^\\+84[0-9]{9}$'::text", name: "users_phone_format"
    t.check_constraint "role::text = ANY (ARRAY['customer'::character varying, 'staff'::character varying, 'admin'::character varying]::text[])", name: "users_role_valid"
  end

  create_table "venues", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "address", null: false
    t.string "phone"
    t.string "time_zone", default: "Asia/Ho_Chi_Minh", null: false
    t.integer "min_booking_minutes", default: 60, null: false
    t.integer "max_booking_minutes", default: 240, null: false
    t.integer "cancellation_cutoff_hours", default: 2, null: false
    t.integer "booking_horizon_days", default: 14, null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", precision: 0, null: false
    t.datetime "updated_at", precision: 0, null: false
    t.integer "max_upcoming_bookings", default: 2, null: false
    t.integer "cancellation_lock_threshold", default: 3, null: false
    t.integer "cancellation_lock_days", default: 7, null: false
    t.string "bank_code"
    t.string "bank_account_number"
    t.string "bank_account_name"
    t.index ["slug"], name: "index_venues_on_slug", unique: true
    t.check_constraint "booking_horizon_days >= 1 AND booking_horizon_days <= 365", name: "venues_booking_horizon_valid"
    t.check_constraint "cancellation_cutoff_hours >= 0 AND cancellation_cutoff_hours <= 168", name: "venues_cancellation_cutoff_valid"
    t.check_constraint "cancellation_lock_days >= 1 AND cancellation_lock_days <= 90", name: "venues_cancellation_lock_days_valid"
    t.check_constraint "cancellation_lock_threshold >= 1 AND cancellation_lock_threshold <= 20", name: "venues_cancellation_lock_threshold_valid"
    t.check_constraint "length(btrim(address::text)) > 0", name: "venues_address_present"
    t.check_constraint "length(btrim(name::text)) > 0", name: "venues_name_present"
    t.check_constraint "max_booking_minutes >= min_booking_minutes AND max_booking_minutes <= 720 AND (max_booking_minutes % 30) = 0", name: "venues_max_booking_minutes_valid"
    t.check_constraint "max_upcoming_bookings >= 1 AND max_upcoming_bookings <= 50", name: "venues_max_upcoming_bookings_valid"
    t.check_constraint "min_booking_minutes >= 30 AND (min_booking_minutes % 30) = 0", name: "venues_min_booking_minutes_valid"
    t.check_constraint "phone::text ~ '^\\+84[0-9]{9}$'::text", name: "venues_phone_format"
    t.check_constraint "slug::text ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text", name: "venues_slug_format"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])", name: "venues_status_valid"
  end

  add_foreign_key "bank_transactions", "payments"
  add_foreign_key "bank_transactions", "users", column: "resolved_by_id"
  add_foreign_key "booking_events", "bookings", on_delete: :cascade
  add_foreign_key "booking_events", "users", column: "actor_id"
  add_foreign_key "booking_series", "users"
  add_foreign_key "booking_series", "users", column: "created_by_id"
  add_foreign_key "booking_series_periods", "booking_series", column: "series_id"
  add_foreign_key "booking_series_periods", "users", column: "paid_by_id"
  add_foreign_key "bookings", "booking_series", column: "series_id"
  add_foreign_key "bookings", "booking_series_periods", column: "series_refund_period_id"
  add_foreign_key "bookings", "courts"
  add_foreign_key "bookings", "payments"
  add_foreign_key "bookings", "users"
  add_foreign_key "bookings", "users", column: "cancelled_by_id"
  add_foreign_key "bookings", "users", column: "created_by_id"
  add_foreign_key "bookings", "users", column: "refunded_by_id"
  add_foreign_key "courts", "venues"
  add_foreign_key "customer_profiles", "users", column: "blocked_by_id"
  add_foreign_key "opening_hours", "venues", on_delete: :cascade
  add_foreign_key "payments", "bank_transactions"
  add_foreign_key "payments", "booking_series", column: "series_id"
  add_foreign_key "payments", "users"
  add_foreign_key "payments", "users", column: "created_by_id"
  add_foreign_key "price_rules", "courts", column: ["court_id", "venue_id"], primary_key: ["id", "venue_id"], name: "fk_price_rules_court_venue"
  add_foreign_key "price_rules", "venues"
end
