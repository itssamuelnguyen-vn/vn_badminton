class CreateTournaments < ActiveRecord::Migration[8.1]
  def change
    # An in-house tournament ("giải đấu nội bộ"): one event (singles, doubles or mixed doubles) on some courts for a
    # few hours, played as a knockout, groups then knockout, or a round robin. Entries pay a fee by transfer.
    create_table :tournaments do |t|
      t.references :venue, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :title_en
      t.text :description
      t.string :play_format, null: false
      t.string :discipline, null: false
      t.string :gender
      t.string :level
      t.bigint :court_ids, array: true, null: false
      t.datetime :starts_at, precision: 0, null: false
      t.datetime :ends_at, precision: 0, null: false
      t.datetime :registration_closes_at, precision: 0, null: false
      t.integer :max_entries, null: false
      t.bigint :fee_vnd, null: false, default: 0
      t.integer :group_size
      t.integer :advance_per_group
      t.string :status, null: false, default: "open"
      t.datetime :drawn_at, precision: 0
      t.datetime :finished_at, precision: 0
      t.datetime :cancelled_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :tournaments, "play_format IN ('knockout', 'groups_knockout', 'round_robin')", name: "tournaments_format_valid"
    add_check_constraint :tournaments, "discipline IN ('singles', 'doubles', 'mixed_doubles')", name: "tournaments_discipline_valid"
    add_check_constraint :tournaments, "gender IS NULL OR (gender IN ('male', 'female') AND discipline <> 'mixed_doubles')", name: "tournaments_gender_valid"
    add_check_constraint :tournaments, "status IN ('open', 'in_progress', 'finished', 'cancelled')", name: "tournaments_status_valid"
    add_check_constraint :tournaments, "ends_at > starts_at", name: "tournaments_range_valid"
    add_check_constraint :tournaments, "registration_closes_at <= starts_at", name: "tournaments_registration_before_start"
    add_check_constraint :tournaments, "max_entries BETWEEN 2 AND 64", name: "tournaments_max_entries_valid"
    add_check_constraint :tournaments, "fee_vnd >= 0 AND fee_vnd % 1000 = 0", name: "tournaments_fee_valid"
    add_check_constraint :tournaments, "cardinality(court_ids) >= 1", name: "tournaments_courts_present"
    add_check_constraint :tournaments, "play_format <> 'groups_knockout' OR (group_size BETWEEN 3 AND 6 AND advance_per_group BETWEEN 1 AND 2)",
                         name: "tournaments_groups_valid"
    add_index :tournaments, :starts_at

    # The courts it keeps are blocks (kind "block") pointing at it.
    add_reference :bookings, :tournament, foreign_key: true

    # A player (singles) or a pair (doubles: the registrant and a partner, with or without an account).
    create_table :tournament_entries do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :partner, foreign_key: { to_table: :users }
      t.string :partner_name
      t.string :partner_phone
      t.string :partner_gender
      t.references :payment, foreign_key: true
      t.bigint :amount_vnd, null: false
      t.string :status, null: false, default: "pending"
      t.integer :seed
      t.integer :group_number
      t.datetime :cancelled_at, precision: 0
      t.bigint :refund_vnd
      t.datetime :refunded_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :tournament_entries, "status IN ('pending', 'confirmed', 'cancelled')", name: "tournament_entries_status_valid"
    add_check_constraint :tournament_entries, "partner_gender IS NULL OR partner_gender IN ('male', 'female')", name: "tournament_entries_partner_gender_valid"
    add_check_constraint :tournament_entries, "seed IS NULL OR seed >= 1", name: "tournament_entries_seed_valid"
    add_reference :payments, :tournament_entry, foreign_key: true
    remove_check_constraint :payments, "purpose IN ('bookings', 'series_period', 'package', 'tickets')", name: "payments_purpose_valid"
    add_check_constraint :payments, "purpose IN ('bookings', 'series_period', 'package', 'tickets', 'tournament')", name: "payments_purpose_valid"

    # One match. Knockout matches point to the match their winner goes on to (next_match, slot "a" or "b").
    create_table :tournament_matches do |t|
      t.references :tournament, null: false, foreign_key: true
      t.string :stage, null: false
      t.integer :group_number
      t.integer :round, null: false
      t.integer :position, null: false
      t.references :entry_a, foreign_key: { to_table: :tournament_entries }
      t.references :entry_b, foreign_key: { to_table: :tournament_entries }
      t.references :winner, foreign_key: { to_table: :tournament_entries }
      t.references :next_match, foreign_key: { to_table: :tournament_matches }
      t.string :next_slot
      t.jsonb :scores, null: false, default: []
      t.boolean :walkover, null: false, default: false
      t.references :court, foreign_key: true
      t.datetime :called_at, precision: 0
      t.datetime :finished_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :tournament_matches, "stage IN ('group', 'knockout')", name: "tournament_matches_stage_valid"
    add_check_constraint :tournament_matches, "next_slot IS NULL OR next_slot IN ('a', 'b')", name: "tournament_matches_next_slot_valid"
    add_check_constraint :tournament_matches, "winner_id IS NULL OR winner_id = entry_a_id OR winner_id = entry_b_id", name: "tournament_matches_winner_plays"
  end
end
