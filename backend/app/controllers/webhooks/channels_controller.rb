module Webhooks
  # Entrada dos canais simulados (chat do app, WhatsApp e e-mail).
  class ChannelsController < ApplicationController
    before_action :verify_signature

    def create
      payload = parse_json(request.raw_post)
      result = Ingestion::ReceiveMessage.call(
        channel: params[:channel],
        provider_message_id: payload["provider_message_id"],
        brand_slug: payload["brand"],
        customer_external_id: payload.dig("customer", "external_id"),
        customer_name: payload.dig("customer", "name"),
        text: payload["text"],
        raw: payload
      )

      # O 2xx só sai depois de a transação confirmar: quem recebeu 2xx pode parar de reenviar.
      render status: result.duplicate ? :ok : :created, json: {
        ticket_id: result.ticket.id,
        message_id: result.message.id,
        seq: result.message.seq,
        duplicate: result.duplicate
      }
    rescue Ingestion::ReceiveMessage::Invalid => error
      render status: :unprocessable_content, json: { error: error.message }
    end

    private

    def verify_signature
      valid = Webhooks::Signature.valid?(
        id: request.headers["X-Webhook-Id"],
        timestamp: request.headers["X-Webhook-Timestamp"],
        body: request.raw_post,
        signature: request.headers["X-Webhook-Signature"],
        secrets: IntegrationConfig.channel_webhook_secrets
      )
      render status: :unauthorized, json: { error: "assinatura inválida" } unless valid
    end

    def parse_json(body)
      parsed = JSON.parse(body)
      raise Ingestion::ReceiveMessage::Invalid, "o corpo precisa ser um objeto JSON" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise Ingestion::ReceiveMessage::Invalid, "o corpo não é JSON válido"
    end
  end
end
