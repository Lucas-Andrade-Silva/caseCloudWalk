class TeamMembership < ApplicationRecord
  self.primary_key = %i[user_id team_id]

  belongs_to :user
  belongs_to :team
end
