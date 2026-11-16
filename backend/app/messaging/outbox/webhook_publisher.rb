require "net/http"

module Outbox
  # Entrega um evento do outbox ao broker como webhook assinado (ADR 0003, E1).
  #
  # Tem a mesma interface de produtor que o Relay espera (#produce_sync). Qualquer resposta
  # diferente de 2xx vira erro:
  # - Rejected: o broker recusou de vez (corpo ou tópico inválido). Repetir não adianta.
  # - DeliveryError: falha temporária (broker fora, 5xx, credencial, limite). O relay tenta de novo.
  class WebhookPublisher
    class DeliveryError < StandardError; end
    class Rejected < DeliveryError; end

    REJECTED_STATUSES = [ 400, 404, 413, 422 ].freeze

    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 10

    def initialize(url: IntegrationConfig.broker_webhook_url,
                   secret: IntegrationConfig.broker_webhook_secret,
                   transport: method(:post))
      @uri = URI(url)
      @secret = secret
      @transport = transport
    end

    def produce_sync(message)
      event_id = message[:headers].fetch("event_id")
      body = {
        topic: message[:topic],
        key: message[:key],
        headers: message[:headers],
        payload: JSON.parse(message[:payload])
      }.to_json

      status = @transport.call(@uri, signed_headers(event_id, body), body)
      return if (200..299).cover?(status)

      error = REJECTED_STATUSES.include?(status) ? Rejected : DeliveryError
      raise error, "broker respondeu #{status} para o evento #{event_id}"
    end

    private

    def signed_headers(id, body)
      timestamp = Time.now.to_i
      {
        "Content-Type" => "application/json",
        "X-Webhook-Id" => id,
        "X-Webhook-Timestamp" => timestamp.to_s,
        "X-Webhook-Signature" => Webhooks::Signature.sign(id: id, timestamp: timestamp, body: body, secret: @secret)
      }
    end

    def post(uri, headers, body)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.post(uri.request_uri, body, headers).code.to_i
      end
    end
  end
end
