module Broker
  # Leva uma resposta do agente (lida do Kafka) até a plataforma e decide o que fazer com o resultado.
  #
  # - 2xx: entregue (200 é duplicata que a plataforma já tinha).
  # - 404, 409 e 422: recusa definitiva. Repetir não muda o resultado, então encerra com aviso.
  # - 401, 403, 429, 502, 503 e 504: a plataforma está fora ou recusando todo mundo (PlatformUnavailable).
  #   Vale para qualquer mensagem, então não adianta separar esta: repete a mesma depois.
  # - Qualquer outra resposta: RetryableError. Pode ser defeito desta mensagem; segue para o retry.
  class ReplyForwarder
    RetryableError = Class.new(StandardError)
    PlatformUnavailable = Class.new(RetryableError)

    TERMINAL_REJECTIONS = [ 404, 409, 422 ].freeze
    UNAVAILABLE_STATUSES = [ 401, 403, 429, 502, 503, 504 ].freeze

    def initialize(client: PlatformClient.new, logger: Broker.logger)
      @client = client
      @logger = logger
    end

    def forward(json_body)
      status = @client.post_reply(json_body)
      return :delivered if (200..299).cover?(status)

      if TERMINAL_REJECTIONS.include?(status)
        @logger.warn("plataforma recusou a resposta do agente com #{status}; não será reenviada")
        return :rejected
      end

      raise PlatformUnavailable, "plataforma respondeu #{status}" if UNAVAILABLE_STATUSES.include?(status)

      raise RetryableError, "plataforma respondeu #{status}"
    end
  end
end
