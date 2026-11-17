module Api
  # Retrato inicial do mapa vivo (ADR 0007): os tickets abertos das marcas que a pessoa enxerga. Depois
  # disso, o navegador acompanha pelo canal MapChannel.
  class MapController < ApplicationController
    LIMIT = 500

    def show
      token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
      user = User.find_by_token(token)
      return render(status: :unauthorized, json: { error: "token inválido" }) if user.nil?
      return render(status: :forbidden, json: { error: "apenas pessoas da operação" }) unless %w[analyst ops].include?(user.role)

      scope = Ticket.open
      scope = scope.where(brand_id: user.brand_ids) if user.analyst?
      tickets = scope.includes(:brand, :queue)
                     .order(:priority, created_at: :desc, id: :asc)
                     .limit(LIMIT)

      render json: { total: scope.count, limit: LIMIT, tickets: tickets.map { |ticket| Live::MapItem.call(ticket) } }
    end
  end
end
