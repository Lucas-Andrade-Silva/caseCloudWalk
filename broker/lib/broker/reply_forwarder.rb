module Broker
  # Leva uma resposta do agente (lida do Kafka) até a plataforma e decide o que fazer com o resultado.
  #
  # - 2xx: entregue (200 é duplicata que a plataforma já tinha).
  # - 404, 409 e 422: recusa definitiva. Repetir não muda o resultado, então encerra com aviso.
  # - Qualquer outra resposta ou erro de rede: levanta erro. O consumidor não confirma o offset e o
  #   Kafka entrega de novo.
  class ReplyForwarder
    RetryableError = Class.new(StandardError)

    TERMINAL_REJECTIONS = [ 404, 409, 422 ].freeze

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

      raise RetryableError, "plataforma respondeu #{status}"
    end
  end
end
