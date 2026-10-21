class CreateCashShifts < ActiveRecord::Migration[8.1]
  def change
    # The cash drawer between an opening and a closing count ("chốt ca"). Cash collected while a shift is open
    # points at it (booking_events.cash_shift_id, booking_series_periods.cash_shift_id), so expected =
    # opening + what was collected; the closing count is compared with it.
    create_table :cash_shifts do |t|
      t.references :venue, null: false, foreign_key: true
      t.references :opened_by, null: false, foreign_key: { to_table: :users }
      t.datetime :opened_at, precision: 0, null: false
      t.bigint :opening_vnd, null: false
      t.references :closed_by, foreign_key: { to_table: :users }
      t.datetime :closed_at, precision: 0
      t.bigint :collected_vnd
      t.bigint :expected_vnd
      t.bigint :counted_vnd
      t.bigint :difference_vnd
      t.text :note
      t.timestamps precision: 0
    end
    # At most one open shift per venue.
    add_index :cash_shifts, :venue_id, unique: true, where: "closed_at IS NULL", name: "index_cash_shifts_one_open_per_venue"
    add_index :cash_shifts, :opened_at
    add_check_constraint :cash_shifts, "opening_vnd >= 0", name: "cash_shifts_opening_valid"
    add_check_constraint :cash_shifts,
                         "(closed_at IS NULL) = (closed_by_id IS NULL) AND (closed_at IS NULL) = (collected_vnd IS NULL) AND " \
                         "(closed_at IS NULL) = (expected_vnd IS NULL) AND (closed_at IS NULL) = (counted_vnd IS NULL) AND " \
                         "(closed_at IS NULL) = (difference_vnd IS NULL)", name: "cash_shifts_closed_consistent"
    add_check_constraint :cash_shifts, "closed_at IS NULL OR closed_at >= opened_at", name: "cash_shifts_range_valid"
    add_check_constraint :cash_shifts, "counted_vnd IS NULL OR counted_vnd >= 0", name: "cash_shifts_counted_valid"
    add_check_constraint :cash_shifts, "expected_vnd = opening_vnd + collected_vnd AND difference_vnd = counted_vnd - expected_vnd",
                         name: "cash_shifts_amounts_valid"
    # A drawer that does not match must be explained.
    add_check_constraint :cash_shifts, "difference_vnd IS NULL OR difference_vnd = 0 OR coalesce(length(btrim(note)), 0) > 0",
                         name: "cash_shifts_note_when_different"

    # A cash payment recorded at the counter (+ what was collected) or its undo in the same shift (− the same).
    add_reference :booking_events, :cash_shift, foreign_key: true
    add_column :booking_events, :cash_vnd, :bigint
    add_check_constraint :booking_events, "(cash_shift_id IS NULL) = (cash_vnd IS NULL)", name: "booking_events_cash_consistent"
    # A series month paid in cash ("Đã thu" on the series page) while a shift was open: its due amount.
    add_reference :booking_series_periods, :cash_shift, foreign_key: true
  end
end
