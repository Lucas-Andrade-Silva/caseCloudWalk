module Api
  # Faz o papel do canal para o chat do cliente simulado (ADR 0007, I7 e I8): a mensagem entra pela mesma
  # ingestão do webhook, e o cliente lê a conversa do atendimento mais recente naquele canal.
  #
  # Sem login, como um cliente de verdade. Por isso só existe com CHANNEL_SIMULATOR_ENABLED=true; desligado,
  # responde 404 como se a rota não existisse.
  class SimulatorController < ApplicationController
    include JsonBody

    before_action :require_enabled

    def create
      body = json_body
      result = Ingestion::ReceiveMessage.call(
        channel: body["channel"],
        provider_message_id: "sim-#{SecureRandom.uuid}",
        brand_slug: body["brand"],
        customer_external_id: body.dig("customer", "external_id"),
        customer_name: body.dig("customer", "name"),
        text: body["text"],
        raw: { "source" => "simulator" }
      )
      render status: :created, json: { ticket_id: result.ticket.id, seq: result.message.seq }
    rescue Ingestion::ReceiveMessage::Invalid => error
      render status: :unprocessable_content, json: { error: error.message }
    end

    def conversation
      ticket = latest_ticket
      return render(json: { ticket_id: nil, mode: nil, messages: [] }) unless ticket

      render json: {
        ticket_id: ticket.id,
        mode: ticket.mode,
        messages: ticket.messages.order(:seq).map do |message|
          { seq: message.seq, sender: message.sender, text: message.body, created_at: message.created_at.iso8601(3) }
        end
      }
    end

    private

    def require_enabled
      head :not_found unless IntegrationConfig.channel_simulator_enabled?
    end

    # O atendimento aberto do cliente naquele canal; se não houver, o último encerrado.
    def latest_ticket
      brand = Brand.find_by(slug: params[:brand])
      customer = brand && Customer.find_by(brand: brand, external_id: params[:external_id])
      return unless customer

      Ticket.where(customer: customer, channel: params[:channel])
            .order(Arel.sql("CASE WHEN mode = 'closed' THEN 1 ELSE 0 END"), created_at: :desc)
            .first
    end
  end
end
