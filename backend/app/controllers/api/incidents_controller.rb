module Api
  # Modo Incidente (ADR 0009, W1). Analista e operação veem os incidentes abertos das marcas que enxergam; só o
  # analista responde e fecha os tickets do incidente.
  class IncidentsController < ApplicationController
    before_action :authenticate

    def index
      scope = Incident.open.includes(:brand).order(opened_at: :desc)
      scope = scope.where(brand_id: @user.brand_ids) if @user.analyst?
      render json: { incidents: scope.map { |incident| serialize(incident) } }
    end

    def resolve
      return render(status: :forbidden, json: { error: "apenas analistas" }) unless @user.analyst?

      incident = Incident.where(brand_id: @user.brand_ids).find_by(id: params[:id])
      return render(status: :not_found, json: { error: "incidente não encontrado" }) unless incident

      body = parse_json(request.raw_post)
      outcome = Incidents::Resolve.call(incident: incident, analyst: @user, text: body["text"],
                                        resolution_code: body["resolution_code"])
      render json: { closed: outcome.closed, skipped: outcome.skipped, incident: serialize(incident.reload) }
    rescue Incidents::Resolve::Invalid => error
      render status: :unprocessable_content, json: { error: error.message }
    rescue Incidents::Resolve::AlreadyResolved
      render status: :conflict, json: { error: "o incidente já foi resolvido" }
    end

    private

    def authenticate
      token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
      @user = User.find_by_token(token)
      return render(status: :unauthorized, json: { error: "token inválido" }) if @user.nil?

      render(status: :forbidden, json: { error: "apenas pessoas da operação" }) unless %w[analyst ops].include?(@user.role)
    end

    def serialize(incident)
      {
        id: incident.id, key: incident.key, label: incident.label, brand: incident.brand.slug, status: incident.status,
        title: incident.title, draft_reply: incident.draft_reply, title_source: incident.title_source,
        model: incident.model, opened_at: incident.opened_at.iso8601(3), resolved_at: incident.resolved_at&.iso8601(3),
        open_tickets: incident.tickets.open.count, total_tickets: incident.tickets.count
      }
    end

    def parse_json(body)
      parsed = JSON.parse(body.presence || "{}")
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
