module Api
  # Painel (ADR 0009, W8): números reais da operação. Analista vê as marcas que atende; a operação vê todas.
  class DashboardController < ApplicationController
    include TokenAuthentication

    authenticate_roles STAFF_ROLES, forbidden: "apenas pessoas da operação"

    def show
      user = current_user
      render json: Dashboard::Metrics.call(brand_ids: user.analyst? ? user.brand_ids : nil)
    end
  end
end
