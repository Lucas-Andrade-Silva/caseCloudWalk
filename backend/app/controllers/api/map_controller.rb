module Api
  # Retrato inicial do mapa vivo (ADR 0007): os tickets abertos das marcas que a pessoa enxerga. Depois
  # disso, o navegador acompanha pelo canal MapChannel.
  class MapController < ApplicationController
    include TokenAuthentication

    authenticate_roles STAFF_ROLES, forbidden: "apenas pessoas da operação"

    LIMIT = 500

    def show
      user = current_user
      scope = Ticket.open
      scope = scope.where(brand_id: user.brand_ids) if user.analyst?
      tickets = scope.includes(:brand, :queue)
                     .order(:priority, created_at: :desc, id: :asc)
                     .limit(LIMIT)

      render json: { total: scope.count, limit: LIMIT, tickets: tickets.map { |ticket| Live::MapItem.call(ticket) } }
    end
  end
end
