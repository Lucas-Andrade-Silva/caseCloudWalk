module Broker
  # Recebe os webhooks da plataforma e publica cada evento no Kafka.
  #
  # Só responde 2xx depois de o Kafka confirmar a gravação. Qualquer outra resposta faz a plataforma
  # reenviar, então nada se perde se o Kafka estiver fora do ar.
  class WebhookApp
    PATH = "/webhooks/helpdesk"
    Invalid = Class.new(StandardError)

    def initialize(producer:, secrets:, allowed_topics:, logger: Broker.logger)
      @producer = producer
      @secrets = secrets
      @allowed_topics = allowed_topics
      @logger = logger
    end

    def call(env)
      request = Rack::Request.new(env)
      return respond(200, "ok") if request.get? && request.path == "/up"
      return respond(404, "not found") unless request.post? && request.path == PATH

      body = request.body.read
      return respond(401, "assinatura inválida") unless signed?(env, body)

      publish(env, message_from(body))
      respond(204)
    rescue Invalid => error
      respond(422, error.message)
    rescue WaterDrop::Errors::BaseError, Rdkafka::RdkafkaError => error
      @logger.error("kafka não confirmou: #{error.class}: #{error.message}")
      respond(503, "kafka indisponível")
    end

    private

    # Continua o trace da plataforma (header HTTP traceparent) e o passa adiante nos headers do Kafka.
    def publish(env, message)
      OpenTelemetry::Context.with_current(Tracing.from_rack(env)) do
        Tracing.tracer.in_span("kafka publish #{message[:topic]}", kind: :producer,
                                                                   attributes: { "messaging.system" => "kafka",
                                                                                 "messaging.destination.name" => message[:topic] }) do
          @producer.produce_sync(message.merge(headers: Tracing.with_context(message[:headers])))
        end
      end
    end

    def signed?(env, body)
      Signature.valid?(
        id: env["HTTP_X_WEBHOOK_ID"],
        timestamp: env["HTTP_X_WEBHOOK_TIMESTAMP"],
        body: body,
        signature: env["HTTP_X_WEBHOOK_SIGNATURE"],
        secrets: @secrets
      )
    end

    def message_from(body)
      event = parse(body)
      topic, key, headers, payload = event.values_at("topic", "key", "headers", "payload")

      raise Invalid, "tópico não permitido: #{topic}" unless @allowed_topics.include?(topic)
      raise Invalid, "key precisa ser um texto não vazio" unless key.is_a?(String) && !key.empty?
      raise Invalid, "payload precisa ser um objeto" unless payload.is_a?(Hash)
      unless headers.is_a?(Hash) && headers.values.all?(String)
        raise Invalid, "headers precisa ser um objeto com valores de texto"
      end

      { topic: topic, key: key, payload: JSON.generate(payload), headers: headers }
    end

    def parse(body)
      event = JSON.parse(body)
      raise Invalid, "o corpo precisa ser um objeto JSON" unless event.is_a?(Hash)

      event
    rescue JSON::ParserError
      raise Invalid, "o corpo não é JSON válido"
    end

    def respond(status, text = nil)
      return [ status, {}, [] ] if text.nil?

      [ status, { "content-type" => "text/plain; charset=utf-8" }, [ text ] ]
    end
  end
end
