module Api
  # Painel (ADR 0009, W8): números reais da operação. Analista vê as marcas que atende; a operação vê todas.
  class DashboardController < ApplicationController
    def show
      token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
      user = User.find_by_token(token)
      return render(status: :unauthorized, json: { error: "token inválido" }) if user.nil?
      return render(status: :forbidden, json: { error: "apenas pessoas da operação" }) unless %w[analyst ops].include?(user.role)

      render json: Dashboard::Metrics.call(brand_ids: user.analyst? ? user.brand_ids : nil)
    end
  end
end
