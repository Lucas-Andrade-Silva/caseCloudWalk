module Api
  module Ops
    class QueuesController < BaseController
      def index
        queues = TicketQueue.includes(:brand, :team).order(:slug)
        render json: queues.map { |queue| queue_json(queue) }
      end

      def create
        brand = Brand.find_by(slug: body["brand"])
        return unprocessable([ { path: "brand", message: "marca desconhecida" } ]) unless brand

        queue = TicketQueue.new(brand: brand, team: Team.find_by(id: body["team_id"]), slug: body["slug"],
                                name: body["name"])
        return unprocessable(record_errors(queue)) unless queue.save

        render status: :created, json: queue_json(queue)
      end

      def update
        queue = TicketQueue.find_by(id: params[:id]) or return render(status: :not_found, json: { error: "fila não encontrada" })
        attributes = {}
        attributes[:name] = body["name"] if body.key?("name")
        attributes[:team] = Team.find_by(id: body["team_id"]) if body.key?("team_id")
        return unprocessable(record_errors(queue)) unless queue.update(attributes)

        render json: queue_json(queue)
      end

      private

      def queue_json(queue)
        { id: queue.id, slug: queue.slug, name: queue.name, brand: queue.brand.slug, default: queue.default,
          team: { id: queue.team.id, slug: queue.team.slug, name: queue.team.name } }
      end
    end
  end
end
