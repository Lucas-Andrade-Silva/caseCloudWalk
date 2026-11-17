class ApplicationController < ActionController::API
  # Banco fora do ar é falha da plataforma inteira, não do pedido: 503 diz a quem chama para tentar de novo
  # depois (o canal reenvia; o broker pausa em vez de mandar a resposta do agente para a DLQ).
  DATABASE_UNAVAILABLE = [
    ActiveRecord::ConnectionNotEstablished, ActiveRecord::DatabaseConnectionError, ActiveRecord::ConnectionTimeoutError
  ].freeze

  rescue_from(*DATABASE_UNAVAILABLE) do |error|
    Rails.logger.error("banco indisponível: #{error.class}: #{error.message}")
    response.headers["Retry-After"] = "5"
    render status: :service_unavailable, json: { error: "plataforma temporariamente indisponível" }
  end
end
