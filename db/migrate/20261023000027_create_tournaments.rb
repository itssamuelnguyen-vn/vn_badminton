class CreateTournaments < ActiveRecord::Migration[8.1]
  def change
    # A customer's own tournament ("giải đấu nội bộ"), a tool for a group of players: they book courts as usual,
    # type the players' names, make the draw and enter the results. The venue plays no part in it.
    create_table :tournaments do |t|
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.string :play_format, null: false
      t.string :discipline, null: false
      t.date :played_on
      t.integer :group_size
      t.integer :advance_per_group
      t.string :status, null: false, default: "setup"
      # Anyone with the link sees the tournament; the organizer link lets a signed-in customer help enter scores.
      t.string :share_token, null: false
      t.string :organizer_token, null: false
      t.datetime :drawn_at, precision: 0
      t.datetime :finished_at, precision: 0
      t.timestamps precision: 0
    end
    add_check_constraint :tournaments, "play_format IN ('knockout', 'groups_knockout', 'round_robin')", name: "tournaments_format_valid"
    add_check_constraint :tournaments, "discipline IN ('singles', 'doubles', 'mixed_doubles')", name: "tournaments_discipline_valid"
    add_check_constraint :tournaments, "status IN ('setup', 'in_progress', 'finished')", name: "tournaments_status_valid"
    add_check_constraint :tournaments, "play_format <> 'groups_knockout' OR (group_size BETWEEN 3 AND 6 AND advance_per_group BETWEEN 1 AND 2)",
                         name: "tournaments_groups_valid"
    add_index :tournaments, :share_token, unique: true
    add_index :tournaments, :organizer_token, unique: true

    # Customers the creator lets enter results (they joined with the organizer link).
    create_table :tournament_organizers do |t|
      t.references :tournament, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps precision: 0
    end
    add_index :tournament_organizers, %i[tournament_id user_id], unique: true

    # The organizers' own bookings where it is played (optional): shown on its page, matches called to their courts.
    add_reference :bookings, :tournament, foreign_key: { on_delete: :nullify }

    # A player (singles) or a pair (doubles), by name only: players need no account.
    create_table :tournament_entries do |t|
      t.references :tournament, null: false, foreign_key: true
      t.string :name, null: false
      t.string :partner_name
      t.integer :seed
      t.integer :group_number
      t.timestamps precision: 0
    end
    add_check_constraint :tournament_entries, "seed IS NULL OR seed >= 1", name: "tournament_entries_seed_valid"

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
