module Api
  # Painel (ADR 0009, W8) e seus detalhes (ADR 0011): números reais da operação. Analista vê as marcas que atende;
  # a operação vê todas.
  class DashboardController < ApplicationController
    before_action :authenticate

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

    def authenticate
      token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
      @user = User.find_by_token(token)
      return render(status: :unauthorized, json: { error: "token inválido" }) if @user.nil?

      render(status: :forbidden, json: { error: "apenas pessoas da operação" }) unless %w[analyst ops].include?(@user.role)
    end

    def scope = @user.analyst? ? @user.brand_ids : nil

    def visible?(agent) = !@user.analyst? || agent.id == @user.id || (agent.brand_ids & @user.brand_ids).any?
  end
end
