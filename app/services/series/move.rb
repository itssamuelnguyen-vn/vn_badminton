module Series
  # Moves the sessions of a series still to come, from a date on, to other courts and/or another weekly time
  # ("đổi giờ cả lịch cố định"). The plan is computed and shown first; nothing changes until #apply!.
  #
  #   move = Series::Move.new(series, by: staff, from: date, court_ids: [3], days_of_week: [3], start_minute: 1140, end_minute: 1260)
  #   move.valid?                  # the new pattern: as many courts and days of the week as the series has now
  #   move.items                   # => [Item, ...] each session to come and where it goes
  #   move.choices = { booking_id => "skip" | court_id }   # what to do with each conflict
  #   move.apply!                  # => true when moved (every conflict resolved, nothing taken meanwhile)
  #
  # Each session keeps its place in the pattern: the n-th court of the series becomes the n-th new court and the
  # n-th day of the week (Monday first) the n-th new day, in the same week. A session that cannot go to its new
  # slot (taken, closed, no price, already started, before the date, in another month: the month's payment would
  # no longer match) is a conflict, to skip (it stays where it is) or to move to another free court.
  # Price: sessions of a month already paid (or paid themselves) keep their amount; the others are priced
  # again (the series' agreed price or the price rules). Each move is recorded in the booking's history.
  class Move
    include ActiveModel::Model
    include ActiveModel::Attributes

    SKIP = "skip"
    # Problems another court can solve (the others are about the time).
    COURT_PROBLEMS = %i[taken court_inactive no_price].freeze

    # status: :ok (to its new slot), :other_court (the court chosen for a conflict), :skipped, :conflict (unresolved).
    Item = Data.define(:booking, :court, :starts_at, :ends_at, :amount_vnd, :keeps_price, :status, :problems, :free_courts) do
      def moves? = status.in?(%i[ok other_court])
      def conflict? = status != :ok
    end

    attribute :from, :date
    attribute :start_minute, :integer
    attribute :end_minute, :integer
    attr_reader :series, :court_ids, :days_of_week, :choices

    validates :from, :start_minute, :end_minute, presence: true
    validate :pattern_valid

    def initialize(series, by:, now: Time.current, **attributes)
      @series = series
      @by = by
      @now = now
      @choices = {}
      super(**attributes)
    end

    def court_ids=(ids)
      @court_ids = Array(ids).compact_blank.map(&:to_i).uniq
      @courts = nil
    end

    def days_of_week=(days)
      @days_of_week = Array(days).compact_blank.map(&:to_i).uniq
    end

    # { "12" => "skip", "13" => "4" } from the plan's form; a court id, or SKIP to keep the session where it is.
    def choices=(choices)
      @choices = choices.to_h.to_h { |id, choice| [ id.to_i, choice.to_s == SKIP ? SKIP : choice.to_i ] }
      @items = nil
    end

    # The move as the form shows it at first: the series' current pattern, from today.
    def self.blank(series, by:, now: Time.current)
      new(series, by: by, now: now, from: series.venue.today, court_ids: series.courts.map(&:id),
                  days_of_week: series.days_of_week, start_minute: series.start_minute, end_minute: series.end_minute)
    end

    # The new courts, in the venue's order.
    def courts
      @courts ||= venue.courts.where(id: court_ids).to_a
    end

    def items
      @items ||= plan
    end

    def unresolved
      items.select { |item| item.status == :conflict }
    end

    def apply!
      return false unless valid?
      if unresolved.any?
        errors.add(:base, :conflicts_left)
        return false
      end

      moved = Booking.transaction do
        left = items.select(&:moves?)
        # A session may move to a slot another session of the series is leaving (e.g. every court shifted by
        # one): those that cannot move yet are tried again once the others have moved.
        nil while left.any? && left.reject! { |item| move(item) }
        if left.any?
          errors.add(:base, :taken_meanwhile)
          raise ActiveRecord::Rollback
        end
        if items.any?(&:moves?)
          series.update!(court_ids: courts.map(&:id), days_of_week: days_of_week.sort, start_minute: start_minute, end_minute: end_minute)
        end
        true
      end
      @items = nil unless moved # planned again with what changed meanwhile
      moved || false
    end

    def moved_count
      items.count(&:moves?)
    end

    private

    def venue
      @venue ||= series.venue
    end

    def zone
      venue.zone
    end

    # The confirmed sessions from the date on that have not started.
    def sessions
      from_time = zone.local(from.year, from.month, from.day)
      series.bookings.confirmed.where(starts_at: from_time..).where("starts_at > ?", @now)
            .includes(:court).order(:starts_at, :court_id).to_a
    end

    def plan
      list = sessions
      targets = list.to_h { |booking| [ booking.id, target(booking) ] }
      leaving = list.reject { |booking| choices[booking.id] == SKIP }.map(&:id)
      taken = occupancy(targets.values, leaving)

      list.map do |booking|
        court, starts_at, ends_at = targets[booking.id]
        candidate, problems, court_fixable = check(booking, court, starts_at, ends_at, taken)
        status = :ok
        if problems.any?
          choice = choices[booking.id]
          if choice == SKIP
            status = :skipped
          elsif choice && choice != court.id && (other = venue.courts.find { |c| c.id == choice })
            candidate, other_problems, = check(booking, other, starts_at, ends_at, taken)
            status = other_problems.empty? ? :other_court : :conflict
            court, problems = other, other_problems.presence || problems
          else
            status = :conflict
          end
        end
        taken[court.id] << (starts_at...ends_at) if status.in?(%i[ok other_court])
        Item.new(booking: booking, court: court, starts_at: starts_at, ends_at: ends_at, amount_vnd: candidate.total_amount_vnd,
                 keeps_price: keeps_price?(booking), status: status, problems: problems,
                 free_courts: status != :ok && court_fixable ? free_courts(court, starts_at, ends_at, taken) : [])
      end
    end

    # Where the session goes: [court, starts_at, ends_at].
    def target(booking)
      @old_court_ids ||= series.courts.map(&:id)
      index = @old_court_ids.index(booking.court_id)
      # A session moved by hand to a court outside the series stays on it (unless the series has one court).
      court = courts.one? ? courts.first : (index ? courts[index] : booking.court)
      local = booking.starts_at.in_time_zone(zone)
      date = local.to_date + day_shift(local.wday)
      day = zone.local(date.year, date.month, date.day)
      [ court, day + start_minute.minutes, day + end_minute.minutes ]
    end

    # Days from the old day of the week to the new one in the same week (Monday first).
    def day_shift(wday)
      old_days, new_days = monday_first(series.days_of_week), monday_first(days_of_week)
      index = old_days.one? ? 0 : old_days.index(wday)
      return 0 unless index

      (new_days[index] + 6) % 7 - (wday + 6) % 7
    end

    def monday_first(days)
      days.sort_by { |day| (day + 6) % 7 }
    end

    # Court-minutes held by other bookings around the new slots, per court, in one query; the sessions that
    # move away (leaving) do not count.
    def occupancy(targets, leaving)
      taken = Hash.new { |hash, court_id| hash[court_id] = [] }
      return taken if targets.empty?

      Booking.holding_slot(@now).where(court_id: venue.courts.map(&:id)).where.not(id: leaving)
             .overlapping(targets.map(&:second).min, targets.map(&:third).max)
             .pluck(:court_id, :starts_at, :ends_at).each { |court_id, from, to| taken[court_id] << (from...to) }
      taken
    end

    # The session at the new slot, checked like a move by the venue (opening hours, active court, price),
    # plus the rules of a series move. Returns [the priced copy, problems, whether another court could do].
    def check(booking, court, starts_at, ends_at, taken)
      candidate = booking.dup.tap do |copy|
        copy.assign_attributes(code: booking.code, court: court, starts_at: starts_at, ends_at: ends_at)
        copy.staff_change = true
        copy.keep_price = keeps_price?(booking)
        copy.validate
      end
      errors = candidate.errors.reject { |error| error.type.in?(%i[slot_taken slot_just_taken]) }
      keys = errors.map(&:type)
      problems = errors.map(&:full_message)
      { started: starts_at <= @now, before_from: starts_at.in_time_zone(zone).to_date < from,
        other_month: month_of(starts_at) != month_of(booking.starts_at),
        taken: taken[court.id].any? { |range| range.begin < ends_at && range.end > starts_at } }.each do |key, problem|
        next unless problem

        keys << key
        problems << message(key)
      end
      [ candidate, problems.uniq, keys.all? { |key| key.in?(COURT_PROBLEMS) } ]
    end

    # Active courts free at that time, for a conflict.
    def free_courts(court, starts_at, ends_at, taken)
      venue.courts.select(&:active?).reject do |other|
        other == court || taken[other.id].any? { |range| range.begin < ends_at && range.end > starts_at }
      end
    end

    def move(item)
      Booking.find(item.booking.id).reschedule(court: item.court, starts_at: item.starts_at, ends_at: item.ends_at,
                                               by: @by, keep_price: item.keeps_price)
    end

    def keeps_price?(booking)
      @paid_months ||= series.periods.pluck(:month)
      booking.payment_paid? || @paid_months.include?(month_of(booking.starts_at))
    end

    def month_of(time)
      time.in_time_zone(zone).to_date.beginning_of_month
    end

    def message(key)
      errors.generate_message(:base, key)
    end

    def pattern_valid
      errors.add(:court_ids, :wrong_count, count: series.court_ids.size) unless court_ids.to_a.size == series.court_ids.size
      errors.add(:court_ids, :inclusion) unless courts.size == court_ids.to_a.size && courts.all?(&:active?)
      errors.add(:days_of_week, :wrong_count, count: series.days_of_week.size) unless days_of_week.to_a.size == series.days_of_week.size
      errors.add(:days_of_week, :inclusion) unless days_of_week.to_a.all? { |day| (0..6).cover?(day) }
      return unless start_minute && end_minute && from

      errors.add(:end_minute, :after_start) unless end_minute > start_minute
      errors.add(:base, :off_slot_grid) unless [ start_minute, end_minute ].all? { |minute| minute % 30 == 0 && (0..1440).cover?(minute) }
      errors.add(:from, :in_past) if from < venue.today
      unchanged = courts.map(&:id).sort == series.court_ids.sort && days_of_week.to_a.sort == series.days_of_week.sort &&
                  start_minute == series.start_minute && end_minute == series.end_minute
      errors.add(:base, :unchanged) if unchanged
      errors.add(:base, :no_sessions) if errors.empty? && items.empty?
    end
  end
end
