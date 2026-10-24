# A customer the creator lets enter a Tournament's results (they joined with its organizer link, GD-02).
class TournamentOrganizer < ApplicationRecord
  belongs_to :tournament
  belongs_to :user
end
