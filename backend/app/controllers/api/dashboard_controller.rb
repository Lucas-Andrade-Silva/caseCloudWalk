module Api
  # Painel (ADR 0009, W8) e seus detalhes (ADR 0011): números reais da operação. Analista vê as marcas que atende;
  # a operação vê todas.
  class DashboardController < ApplicationController
    include TokenAuthentication

    authenticate_roles STAFF_ROLES, forbidden: "apenas pessoas da operação"

    def show
      render json: Dashboard::Metrics.call(brand_ids: scope)
    end

    def resolution
      render json: Dashboard::ResolutionDetail.call(brand_ids: scope)
    end

    def team
      render json: Dashboard::TeamDetail.call(brand_ids: scope)
    end

    def tickets
      render json: Dashboard::TicketsDetail.call(brand_ids: scope)
    end

    # Um colega só é visível por marcas em comum; os de outras marcas respondem 404, sem dizer que existem.
    def analyst
      agent = User.find_by(id: params[:id], role: "analyst")
      return render(status: :not_found, json: { error: "analista não encontrado" }) unless agent && visible?(agent)

      render json: Dashboard::AnalystDetail.call(agent: agent, brand_ids: scope)
    end

    private

    def scope = current_user.analyst? ? current_user.brand_ids : nil

    def visible?(agent) = !current_user.analyst? || agent.id == current_user.id || (agent.brand_ids & current_user.brand_ids).any?
  end
end
