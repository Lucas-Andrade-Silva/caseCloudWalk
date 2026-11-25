# Autenticação por token Bearer das rotas da API: 401 sem token válido, 403 quando o papel não pode entrar.
# Cada controlador diz quais papéis aceita e a mensagem do 403; quem passa fica em `current_user`.
module TokenAuthentication
  extend ActiveSupport::Concern

  STAFF_ROLES = %w[analyst ops].freeze

  class_methods do
    def authenticate_roles(roles, forbidden:, **options)
      before_action(**options) { authenticate_roles!(Array(roles), forbidden) }
    end
  end

  private

  attr_reader :current_user

  def authenticate_roles!(roles, forbidden_message)
    @current_user = User.find_by_token(bearer_token)
    return render(status: :unauthorized, json: { error: "token inválido" }) if @current_user.nil?

    render(status: :forbidden, json: { error: forbidden_message }) unless roles.include?(@current_user.role)
  end

  def bearer_token
    request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
  end
end
