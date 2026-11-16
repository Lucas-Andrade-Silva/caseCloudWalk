module Api
  # Quem é o dono do token: a interface usa para entrar e montar a navegação por papel (ADR 0007).
  class MeController < ApplicationController
    PEOPLE = %w[analyst ops].freeze

    def show
      token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
      user = User.find_by_token(token)
      return render(status: :unauthorized, json: { error: "token inválido" }) if user.nil?
      return render(status: :forbidden, json: { error: "apenas pessoas da operação" }) unless PEOPLE.include?(user.role)

      brands = Brand.where(id: user.brand_ids).order(:slug).pluck(:slug)
      render json: { id: user.id, name: user.name, role: user.role, brands: brands }
    end
  end
end
