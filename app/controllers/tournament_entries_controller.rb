# The players of a tournament (GD-03), set by its creator before the draw: typed one per line, a seed or a name
# changed, one removed.
class TournamentEntriesController < ApplicationController
  include RunsTournaments

  before_action :authenticate_user!
  before_action :set_tournament
  before_action :require_creator

  def create
    entries, errors = TournamentEntry.add_list(@tournament, params[:list])
    if errors.empty?
      redirect_to tournament_path(@tournament, anchor: "players"), notice: t(".success", count: entries.size)
    else
      flash[:list] = params[:list].to_s.first(5000)
      redirect_to tournament_path(@tournament, anchor: "players"), alert: errors.to_sentence
    end
  end

  def update
    entry = @tournament.entries.find(params[:id])
    if !@tournament.entries_editable?
      redirect_to tournament_path(@tournament, anchor: "players"), alert: t("tournaments.errors.not_setup")
    elsif entry.update(params.require(:entry).permit(:name, :partner_name, :seed))
      redirect_to tournament_path(@tournament, anchor: "players")
    else
      redirect_to tournament_path(@tournament, anchor: "players"), alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = @tournament.entries.find(params[:id])
    return redirect_to(tournament_path(@tournament, anchor: "players"), alert: t("tournaments.errors.not_setup")) unless @tournament.entries_editable?

    entry.destroy!
    redirect_to tournament_path(@tournament, anchor: "players"), notice: t(".success")
  end
end
