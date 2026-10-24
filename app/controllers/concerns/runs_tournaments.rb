# What the web and app controllers of tournaments share (GD-01..): finding the tournament by its share token, who
# may do what (the creator sets it up, organizers enter results), and the creator's form fields.
module RunsTournaments
  extend ActiveSupport::Concern

  private

  def set_tournament
    @tournament = Tournament.find_shared(params[:tournament_token] || params[:token])
  end

  def require_creator
    refuse_tournament_action unless @tournament.creator?(current_user)
  end

  def require_organizer
    refuse_tournament_action unless @tournament.organizer?(current_user)
  end

  # Web: back to its page with a message. Api::V1 controllers answer 403 instead.
  def refuse_tournament_action
    redirect_to tournament_path(@tournament), alert: t("tournaments.not_allowed")
  end

  # The event and format only before the draw; the event only while no player is typed (pairs need two names).
  def tournament_params
    fields = %i[title description played_on]
    fields += %i[play_format group_size advance_per_group] if @tournament.nil? || @tournament.setup?
    fields << :discipline if @tournament.nil? || @tournament.entries.none?
    params.require(:tournament).permit(*fields)
  end

  # The bookings the current user links (their own, see Tournament#linkable_bookings): the others of theirs
  # linked before are unlinked; other organizers' bookings stay.
  def link_own_bookings(ids)
    linkable = @tournament.linkable_bookings(current_user)
    wanted = Array(ids).compact_blank.map(&:to_i)
    Booking.transaction do
      linkable.where(tournament: @tournament).where.not(id: wanted).find_each { |booking| booking.update!(tournament: nil) }
      linkable.where(id: wanted).find_each { |booking| booking.update!(tournament: @tournament) }
    end
  end
end
