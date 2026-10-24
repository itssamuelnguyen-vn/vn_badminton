module Tournaments
  # The draw (GD-04): the creator draws once the players are typed. They are placed by seed (seeds first, the
  # others shuffled) and the matches made:
  #
  # - knockout: a bracket of the next power of two, the top seeds placed apart (1 and 2 only meet in the final)
  #   and given the byes;
  # - round_robin: one group, everyone meets everyone (circle method: nobody plays twice in a round);
  # - groups_knockout: groups of about group_size, seeds spread snake-wise (1→A, 2→B, …, back from the last group),
  #   each a round robin; once every group match is played (.after_result) the best advance_per_group of each
  #   group go on to a knockout bracket where two players of the same group do not meet in the first round.
  #
  # The tournament finishes with its last match. Until a match is played the draw can be undone (Tournament#undo_draw!).
  module Draw
    class Error < StandardError; end

    module_function

    def call(tournament, now: Time.current, random: Random.new)
      tournament.with_lock do
        raise Error, I18n.t("tournaments.draw.not_setup") unless tournament.setup?

        entries = seeded(tournament.entries.reload.to_a, random)
        check_enough(tournament, entries)

        if tournament.knockout?
          build_bracket(tournament, entries, now: now)
        else
          groups = tournament.round_robin? ? [ entries ] : snake(entries, (entries.size / tournament.group_size.to_f).ceil)
          groups.each.with_index(1) do |members, number|
            members.each { |entry| entry.update!(group_number: number) }
            build_round_robin(tournament, members, number)
          end
        end
        tournament.update!(status: :in_progress, drawn_at: now)
      end
    end

    # After each result: the knockout of groups_knockout once the groups are played, the end of the tournament.
    def after_result(tournament, now: Time.current)
      matches = tournament.matches.reload
      return if matches.any? { |match| !match.finished? }

      if tournament.groups_knockout? && matches.none?(&:knockout?)
        standings = Standings.new(tournament).groups
        qualifiers = (0...tournament.advance_per_group).flat_map { |rank| standings.values.filter_map { |rows| rows[rank]&.entry } }
        build_bracket(tournament, qualifiers, now: now)
      else
        tournament.update!(status: :finished, finished_at: now)
      end
    end

    # Seeds in order, then the others in random order.
    def seeded(entries, random)
      seeds, others = entries.partition(&:seed)
      seeds.sort_by { |entry| [ entry.seed, entry.id ] } + others.shuffle(random: random)
    end

    def check_enough(tournament, entries)
      raise Error, I18n.t("tournaments.draw.too_few") if entries.size < 2
      return unless tournament.groups_knockout?

      groups = (entries.size / tournament.group_size.to_f).ceil
      raise Error, I18n.t("tournaments.draw.too_few_for_groups") if groups * tournament.advance_per_group < 2
    end

    # Snake order: 1 2 3 3 2 1 1 2 3 …
    def snake(entries, count)
      groups = Array.new(count) { [] }
      entries.each_with_index do |entry, index|
        lap, place = index.divmod(count)
        groups[lap.even? ? place : count - 1 - place] << entry
      end
      groups
    end

    def build_round_robin(tournament, members, group_number)
      round_robin_rounds(members).each.with_index(1) do |pairs, round|
        pairs.each.with_index(1) do |(a, b), position|
          tournament.matches.create!(stage: :group, group_number: group_number, round: round, position: position, entry_a: a, entry_b: b)
        end
      end
    end

    # Circle method: the first stays, the others turn; an odd count gets a rest (nil) each round.
    def round_robin_rounds(members)
      list = members.dup
      list << nil if list.size.odd?
      (list.size - 1).times.map do
        pairs = (list.size / 2).times.map { |i| [ list[i], list[-1 - i] ] }.reject { |pair| pair.any?(&:nil?) }
        list = [ list.first, list.last, *list[1..-2] ]
        pairs
      end
    end

    # entries in seed order. Byes go to the top seeds and are won at once.
    def build_bracket(tournament, entries, now:)
      size = 2**Math.log2(entries.size).ceil
      slots = seed_positions(size).map { |seed| entries[seed - 1] }
      keep_groups_apart(slots) if tournament.groups_knockout?
      rounds = Math.log2(size).to_i

      later = nil
      rounds.downto(1) do |round|
        later = (size / 2**round).times.map do |index|
          tournament.matches.create!(stage: :knockout, round: round, position: index + 1,
                                     next_match: later&.at(index / 2), next_slot: (later && (index.even? ? "a" : "b")))
        end
      end
      later.each_with_index do |match, index|
        a, b = slots[index * 2, 2]
        match.update!(entry_a: a, entry_b: b)
        next if a && b

        match.update!(winner: a || b, finished_at: now)
        match.next_match&.update!("entry_#{match.next_slot}" => match.winner)
      end
    end

    # The standard seeding: 1 v 8, 4 v 5, 2 v 7, 3 v 6 for 8 places, so the best meet last.
    def seed_positions(size)
      positions = [ 1 ]
      positions = positions.flat_map { |seed| [ seed, positions.size * 2 + 1 - seed ] } while positions.size < size
      positions
    end

    # Two qualifiers of the same group facing each other in the first round: the lower one swaps with the lower
    # one of another match, when that leaves both matches between different groups.
    def keep_groups_apart(slots)
      pairs = slots.each_slice(2).to_a
      pairs.each_with_index do |(top, low), index|
        next unless top && low && top.group_number == low.group_number

        other = pairs.each_index.find do |j|
          j != index && pairs[j][1] && pairs[j][0] && pairs[j][0].group_number != low.group_number && pairs[j][1].group_number != top.group_number
        end
        pairs[index][1], pairs[other][1] = pairs[other][1], low if other
      end
      slots.replace(pairs.flatten(1))
    end
  end
end
