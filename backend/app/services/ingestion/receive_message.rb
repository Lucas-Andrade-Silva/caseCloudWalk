module Ingestion
  # Recebe uma mensagem de um canal. Numa única transação: registra o webhook (dedupe), encontra ou
  # abre o ticket, grava a mensagem com o próximo seq, escreve a linha do tempo e enfileira o evento
  # para o agente no outbox. Ou tudo isso vale, ou nada.
  class ReceiveMessage
    class Invalid < StandardError; end

    Result = Data.define(:ticket, :message, :duplicate)

    MAX_TEXT_LENGTH = 10_000

    def self.call(...) = new(...).call

    def initialize(channel:, provider_message_id:, brand_slug:, customer_external_id:, text:,
                   customer_name: nil, raw: {})
      @channel = channel.to_s
      @provider_message_id = provider_message_id.to_s.strip
      @brand_slug = brand_slug.to_s.strip
      @customer_external_id = customer_external_id.to_s.strip
      @customer_name = customer_name.presence
      @text = text.to_s.strip
      @raw = raw
    end

    def call
      validate!

      ApplicationRecord.transaction do
        brand = Brand.find_by(slug: @brand_slug) or raise Invalid, "marca desconhecida: #{@brand_slug}"
        inbound_event_id = register_inbound(brand)
        next duplicate_result if inbound_event_id.nil?

        customer = find_or_create_customer(brand)
        ticket, opened = find_or_open_ticket(brand, customer)
        message = ticket.append_message!(sender: "customer", body: @text, inbound_event_id: inbound_event_id)

        ticket.record_event!(kind: "ticket.opened", actor: "customer", data: { channel: @channel }) if opened
        ticket.record_event!(kind: "message.received", actor: "customer",
                             data: { message_id: message.id, seq: message.seq })
        if ticket.ai?
          AgentEvents.message_created!(ticket: ticket, message: message)
          # O vigia do agente conta a espera a partir da mensagem mais antiga ainda sem resposta.
          ticket.update!(awaiting_agent_since: message.created_at) if ticket.awaiting_agent_since.nil?
        end

        Result.new(ticket: ticket, message: message, duplicate: false)
      end
    end

    private

    def validate!
      raise Invalid, "canal desconhecido: #{@channel}" unless Ticket::CHANNELS.include?(@channel)
      raise Invalid, "provider_message_id é obrigatório" if @provider_message_id.empty?
      raise Invalid, "brand é obrigatório" if @brand_slug.empty?
      raise Invalid, "customer.external_id é obrigatório" if @customer_external_id.empty?
      raise Invalid, "text é obrigatório" if @text.empty?
      raise Invalid, "text passa de #{MAX_TEXT_LENGTH} caracteres" if @text.length > MAX_TEXT_LENGTH
    end

    # Insere o registro do webhook. Devolve nil se ele já existia. Uma entrega concorrente da mesma
    # mensagem espera esta transação terminar antes de saber se é duplicata.
    def register_inbound(brand)
      InboundEvent.insert(
        { brand_id: brand.id, channel: @channel, provider_message_id: @provider_message_id, payload: @raw },
        unique_by: %i[channel provider_message_id],
        returning: %i[id]
      ).rows.dig(0, 0)
    end

    def duplicate_result
      inbound = InboundEvent.find_by!(channel: @channel, provider_message_id: @provider_message_id)
      message = inbound.message
      Result.new(ticket: message.ticket, message: message, duplicate: true)
    end

    def find_or_create_customer(brand)
      Customer.create_or_find_by!(brand: brand, external_id: @customer_external_id) do |customer|
        customer.name = @customer_name
      end
    end

    # O índice único parcial garante um ticket aberto por cliente, marca e canal. Quem perde a
    # disputa de criação usa o ticket de quem ganhou.
    def find_or_open_ticket(brand, customer)
      scope = Ticket.open.where(brand: brand, customer: customer, channel: @channel)
      existing = scope.first
      return [ existing, false ] if existing

      [ Ticket.transaction(requires_new: true) { scope.create! }, true ]
    rescue ActiveRecord::RecordNotUnique
      [ scope.first!, false ]
    end
  end
end
