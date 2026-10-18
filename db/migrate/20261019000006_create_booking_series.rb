# Weekly bookings of a regular customer ("khách cố định"), paid at the start of each calendar month.
# Each session is an ordinary booking with series_id. A session the customer skips is released for others;
# if someone else books and plays that time, its price is credited to the next unpaid month.
class CreateBookingSeries < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_series do |t|
      t.string :customer_name, null: false
      t.string :customer_phone, null: false
      t.references :user, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.bigint :court_ids, array: true, null: false
      t.integer :days_of_week, limit: 2, array: true, null: false
      t.integer :start_minute, null: false
      t.integer :end_minute, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.bigint :price_per_hour_vnd # nil: the venue's price rules
      t.text :note
      t.timestamps precision: 0

      t.check_constraint "length(btrim(customer_name)) > 0", name: "booking_series_customer_name_present"
      t.check_constraint "customer_phone ~ '^\\+84[0-9]{9}$'", name: "booking_series_customer_phone_format"
      t.check_constraint "cardinality(court_ids) >= 1", name: "booking_series_courts_present"
      t.check_constraint "cardinality(days_of_week) BETWEEN 1 AND 7 AND days_of_week <@ ARRAY[0,1,2,3,4,5,6]::smallint[]", name: "booking_series_days_valid"
      t.check_constraint "start_minute >= 0 AND end_minute <= 1440 AND end_minute > start_minute AND start_minute % 30 = 0 AND end_minute % 30 = 0", name: "booking_series_time_range_valid"
      t.check_constraint "ends_on >= starts_on", name: "booking_series_date_range_valid"
      t.check_constraint "price_per_hour_vnd IS NULL OR (price_per_hour_vnd > 0 AND price_per_hour_vnd % 1000 = 0)", name: "booking_series_price_valid"
    end

    # One payment per series and calendar month.
    create_table :booking_series_periods do |t|
      t.references :series, null: false, foreign_key: { to_table: :booking_series }
      t.date :month, null: false
      t.bigint :amount_vnd, null: false  # the month's sessions
      t.bigint :credit_vnd, null: false, default: 0  # refunds of earlier months taken off
      t.datetime :paid_at, precision: 0, null: false
      t.references :paid_by, null: false, foreign_key: { to_table: :users }
      t.timestamps precision: 0

      t.index %i[series_id month], unique: true
      t.check_constraint "extract(day from month) = 1", name: "booking_series_periods_month_start"
      t.check_constraint "amount_vnd >= 0 AND credit_vnd >= 0 AND credit_vnd <= amount_vnd", name: "booking_series_periods_amounts_valid"
    end

    change_table :bookings, bulk: true do |t|
      t.references :series, foreign_key: { to_table: :booking_series }
      t.bigint :series_refund_vnd # set once the session is over: what the customer gets back for a skipped session
      t.references :series_refund_period, foreign_key: { to_table: :booking_series_periods } # the payment it was taken off
      t.check_constraint "series_id IS NULL OR kind = 'reservation'", name: "bookings_series_reservations_only"
      t.check_constraint "series_refund_vnd IS NULL OR (series_refund_vnd >= 0 AND series_id IS NOT NULL)", name: "bookings_series_refund_valid"
    end
  end
end
