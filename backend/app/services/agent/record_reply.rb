module Agent
  # Registra o que o agente de IA fez num ticket: responder (`reply`) ou pedir escalação (`escalate`).
  #
  # - Idempotente pelo agent_turn_id: a mesma resposta entregue de novo não repete o efeito.
  # - Descarta e audita se o ticket saiu do modo ai ou se o handoff_epoch mudou: o bot nunca escreve
  #   depois que um humano assumiu.
  # - Resposta a uma mensagem que já não é a última do cliente é entregue e marcada como atrasada
  #   (ADR 0003, E3).
  # - O pedido de escalação grava a despedida, se houver, e passa o ticket para a fila humana (ADR 0004, H1).
  class RecordReply
    class Invalid < StandardError; end
    class TicketNotFound < StandardError; end

    Result = Data.define(:status, :message, :reason, :escalated)

    CONSUMER = "agent.replies"
    ACTIONS = %w[reply escalate].freeze
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    REASON = /\A[a-z0-9_]{1,64}\z/
    MAX_TEXT_LENGTH = 10_000

    def self.call(...) = new(...).call

    def initialize(agent_turn_id:, ticket_id:, in_reply_to_seq:, handoff_epoch:, action:, text:, reason: nil)
      @agent_turn_id = agent_turn_id.to_s
      @ticket_id = ticket_id.to_s
      @in_reply_to_seq = in_reply_to_seq
      @handoff_epoch = handoff_epoch
      @action = action.to_s
      @text = text.to_s.strip
      @reason = reason.to_s
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

    def escalate? = @action == "escalate"

    def validate!
      raise Invalid, "agent_turn_id precisa ser um UUID" unless UUID.match?(@agent_turn_id)
      raise Invalid, "ticket_id precisa ser um UUID" unless UUID.match?(@ticket_id)
      raise Invalid, "in_reply_to_seq precisa ser um inteiro positivo" unless positive_integer?(@in_reply_to_seq)
      raise Invalid, "handoff_epoch precisa ser um inteiro" unless @handoff_epoch.is_a?(Integer)
      raise Invalid, "ação não suportada: #{@action}" unless ACTIONS.include?(@action)
      raise Invalid, "text é obrigatório" if @text.empty? && !escalate?
      raise Invalid, "text passa de #{MAX_TEXT_LENGTH} caracteres" if @text.length > MAX_TEXT_LENGTH
      raise Invalid, "reason precisa seguir o formato [a-z0-9_]{1,64}" if escalate? && !REASON.match?(@reason)
    end

    def positive_integer?(value) = value.is_a?(Integer) && value.positive?

    def apply(ticket)
      return discard(ticket, "ticket_not_in_ai_mode") unless ticket.ai?
      return discard(ticket, "handoff_epoch_mismatch") unless ticket.handoff_epoch == @handoff_epoch

      unless ticket.messages.exists?(seq: @in_reply_to_seq, sender: "customer")
        raise Invalid, "in_reply_to_seq não aponta para uma mensagem do cliente"
      end

      message = record_message(ticket) unless @text.empty?
      return Result.new(status: :created, message: message, reason: nil, escalated: false) unless escalate?

      Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: @reason, actor: "bot",
                             data: { agent_turn_id: @agent_turn_id })
      Result.new(status: :created, message: message, reason: nil, escalated: true)
    end

    def record_message(ticket)
      stale = @in_reply_to_seq < ticket.last_customer_seq
      message = ticket.append_message!(sender: "bot", body: @text, in_reply_to_seq: @in_reply_to_seq,
                                       agent_turn_id: @agent_turn_id, stale: stale)
      ticket.agent_answered_through!(@in_reply_to_seq)
      ticket.record_event!(kind: "message.sent", actor: "bot",
                           data: { message_id: message.id, seq: message.seq, stale: stale,
                                   in_reply_to_seq: @in_reply_to_seq, agent_turn_id: @agent_turn_id })
      message
    end

    def discard(ticket, reason)
      ticket.record_event!(kind: "reply.discarded", actor: "bot",
                           data: { agent_turn_id: @agent_turn_id, action: @action, reason: reason,
                                   mode: ticket.mode, ticket_epoch: ticket.handoff_epoch,
                                   reply_epoch: @handoff_epoch })
      Result.new(status: :discarded, message: nil, reason: reason, escalated: false)
    end

    # O mesmo agent_turn_id já foi processado: devolve o que aconteceu naquela vez.
    def previous_outcome
      events = ConversationEvent.where(ticket_id: @ticket_id).where("data->>'agent_turn_id' = ?", @agent_turn_id)
      discarded = events.find_by(kind: "reply.discarded")
      if discarded
        return Result.new(status: :discarded, message: nil, reason: discarded.data["reason"], escalated: false)
      end

      Result.new(status: :duplicate, message: Message.find_by(agent_turn_id: @agent_turn_id), reason: nil,
                 escalated: events.exists?(kind: "ticket.escalated"))
    end
  end
end
