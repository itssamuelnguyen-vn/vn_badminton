# A player (singles) or a pair (doubles) of a Tournament (GD-03), by name only: players need no account. The
# creator types them before the draw, one per line ("Hùng" or "Hùng / Lan" for a pair) and may set seeds.
class TournamentEntry < ApplicationRecord
  # "Hùng / Lan", "Hùng & Lan", "Hùng + Lan", "Hùng, Lan" or "Hùng - Lan".
  PAIR_SEPARATOR = %r{\s*(?:/|&|\+|,|\s-\s)\s*}

  belongs_to :tournament

  normalizes :name, :partner_name, with: ->(name) { name.squish.presence }

  validates :name, presence: true, length: { maximum: 50 }
  validates :partner_name, length: { maximum: 50 }
  validates :partner_name, presence: true, if: -> { tournament.doubles? }
  validates :partner_name, absence: true, unless: -> { tournament.doubles? }
  validates :seed, numericality: { only_integer: true, in: 1..Tournament::MAX_ENTRIES }, allow_nil: true

  # Adds the entries of a typed list, one per line (blank lines skipped). All or nothing: the returned entries
  # carry errors (with their line) when one cannot be added.
  def self.add_list(tournament, text)
    lines = text.to_s.lines.map(&:squish).compact_blank
    entries = lines.map do |line|
      name, partner = tournament.doubles? ? line.split(PAIR_SEPARATOR, 2) : [ line, nil ]
      tournament.entries.build(name: name, partner_name: partner)
    end
    errors = list_errors(tournament, entries)
    if errors.empty?
      transaction { entries.each(&:save!) }
    else
      tournament.entries.reset
    end
    [ entries, errors ]
  end

  def self.list_errors(tournament, entries)
    return [ I18n.t("tournaments.errors.not_setup") ] unless tournament.entries_editable?
    return [ I18n.t("tournaments.errors.empty_list") ] if entries.empty?

    total = tournament.entries.count + entries.size
    limit = tournament.round_robin? ? Tournament::ROUND_ROBIN_MAX : Tournament::MAX_ENTRIES
    return [ I18n.t("tournaments.errors.too_many_entries", count: limit) ] if total > limit

    entries.each_with_index.reject { |entry, _| entry.valid? }.map do |entry, index|
      I18n.t("tournaments.errors.line", number: index + 1, errors: entry.errors.full_messages.to_sentence)
    end
  end

  def display_name
    partner_name ? "#{name} / #{partner_name}" : name
  end
end
