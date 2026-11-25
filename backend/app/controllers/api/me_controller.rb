module Api
  # Quem é o dono do token: a interface usa para entrar e montar a navegação por papel (ADR 0007).
  class MeController < ApplicationController
    include TokenAuthentication

    authenticate_roles STAFF_ROLES, forbidden: "apenas pessoas da operação"

    def show
      user = current_user
      brands = Brand.where(id: user.brand_ids).order(:slug).pluck(:slug)
      render json: { id: user.id, name: user.name, role: user.role, brands: brands }
    end
  end
end
