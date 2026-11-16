module Agent
  # Registra a resposta do agente de IA num ticket.
  #
  # - Idempotente pelo agent_turn_id: a mesma resposta entregue de novo não repete o efeito.
  # - Descarta e audita a resposta se o ticket saiu do modo ai ou se o handoff_epoch mudou: o bot
  #   nunca escreve depois que um humano assumiu.
  # - Resposta a uma mensagem que já não é a última do cliente é entregue e marcada como atrasada
  #   (ADR 0003, E3).
  class RecordReply
    class Invalid < StandardError; end
    class TicketNotFound < StandardError; end

    Result = Data.define(:status, :message, :reason)

    CONSUMER = "agent.replies"
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    MAX_TEXT_LENGTH = 10_000

    def self.call(...) = new(...).call

    def initialize(agent_turn_id:, ticket_id:, in_reply_to_seq:, handoff_epoch:, action:, text:)
      @agent_turn_id = agent_turn_id.to_s
      @ticket_id = ticket_id.to_s
      @in_reply_to_seq = in_reply_to_seq
      @handoff_epoch = handoff_epoch
      @action = action.to_s
      @text = text.to_s.strip
    end

    def call
      validate!
      ticket = Ticket.find_by(id: @ticket_id) or raise TicketNotFound

      result = nil
      first_delivery = Inbox.process(consumer: CONSUMER, event_id: @agent_turn_id) do
        result = ticket.with_lock { apply(ticket) }
      end
      first_delivery ? result : previous_outcome
    end

    private

    def validate!
      raise Invalid, "agent_turn_id precisa ser um UUID" unless UUID.match?(@agent_turn_id)
      raise Invalid, "ticket_id precisa ser um UUID" unless UUID.match?(@ticket_id)
      raise Invalid, "in_reply_to_seq precisa ser um inteiro positivo" unless positive_integer?(@in_reply_to_seq)
      raise Invalid, "handoff_epoch precisa ser um inteiro" unless @handoff_epoch.is_a?(Integer)
      raise Invalid, "ação não suportada: #{@action}" unless @action == "reply"
      raise Invalid, "text é obrigatório" if @text.empty?
      raise Invalid, "text passa de #{MAX_TEXT_LENGTH} caracteres" if @text.length > MAX_TEXT_LENGTH
    end

    def positive_integer?(value) = value.is_a?(Integer) && value.positive?

    def apply(ticket)
      return discard(ticket, "ticket_not_in_ai_mode") unless ticket.ai?
      return discard(ticket, "handoff_epoch_mismatch") unless ticket.handoff_epoch == @handoff_epoch

      unless ticket.messages.exists?(seq: @in_reply_to_seq, sender: "customer")
        raise Invalid, "in_reply_to_seq não aponta para uma mensagem do cliente"
      end

      stale = @in_reply_to_seq < ticket.last_customer_seq
      message = ticket.append_message!(sender: "bot", body: @text, in_reply_to_seq: @in_reply_to_seq,
                                       agent_turn_id: @agent_turn_id, stale: stale)
      ticket.record_event!(kind: "message.sent", actor: "bot",
                           data: { message_id: message.id, seq: message.seq, stale: stale,
                                   in_reply_to_seq: @in_reply_to_seq, agent_turn_id: @agent_turn_id })
      Result.new(status: :created, message: message, reason: nil)
    end

    def discard(ticket, reason)
      ticket.record_event!(kind: "reply.discarded", actor: "bot",
                           data: { agent_turn_id: @agent_turn_id, reason: reason, mode: ticket.mode,
                                   ticket_epoch: ticket.handoff_epoch, reply_epoch: @handoff_epoch })
      Result.new(status: :discarded, message: nil, reason: reason)
    end

    # A resposta já foi processada antes: devolve o que aconteceu naquela vez.
    def previous_outcome
      message = Message.find_by(agent_turn_id: @agent_turn_id)
      return Result.new(status: :duplicate, message: message, reason: nil) if message

      discarded = ConversationEvent.where(kind: "reply.discarded")
                                   .find_by("data->>'agent_turn_id' = ?", @agent_turn_id)
      Result.new(status: :discarded, message: nil, reason: discarded&.data&.fetch("reason", nil))
    end
  end
end
