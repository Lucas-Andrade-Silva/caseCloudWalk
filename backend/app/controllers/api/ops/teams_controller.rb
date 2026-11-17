module Api
  module Ops
    class TeamsController < BaseController
      def index
        teams = Team.includes(:members, :queues).order(:name)
        render json: teams.map { |team| team_json(team) }
      end

      def create
        team = Team.new(slug: body["slug"], name: body["name"])
        return unprocessable(record_errors(team)) unless team.save

        render status: :created, json: team_json(team)
      end

      def add_member
        team = Team.find_by(id: params[:id]) or return render(status: :not_found, json: { error: "equipe não encontrada" })
        analyst = User.find_by(id: body["user_id"], role: "analyst")
        return unprocessable([ { path: "user_id", message: "analista não encontrado" } ]) unless analyst

        TeamMembership.find_or_create_by!(team: team, user: analyst)
        head :no_content
      end

      def remove_member
        TeamMembership.where(team_id: params[:id], user_id: params[:user_id]).delete_all
        head :no_content
      end

      private

      def team_json(team)
        {
          id: team.id, slug: team.slug, name: team.name,
          members: team.members.map { |user| { id: user.id, name: user.name } },
          queues: team.queues.map(&:slug)
        }
      end
    end
  end
end
