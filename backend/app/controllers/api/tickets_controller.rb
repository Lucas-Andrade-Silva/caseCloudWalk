module Api
  # Ações do analista sobre um ticket: ver, assumir, responder e fechar.
  class TicketsController < AnalystController
    before_action :load_ticket

    def show
      render json: ticket_summary(@ticket).merge(
        messages: @ticket.messages.order(:seq).map do |message|
          { id: message.id, seq: message.seq, sender: message.sender, text: message.body, stale: message.stale,
            created_at: message.created_at.iso8601(3) }
        end,
        events: @ticket.conversation_events.order(:id).map do |event|
          { kind: event.kind, actor: event.actor, data: event.data, created_at: event.created_at.iso8601(3) }
        end,
        memory: Memory::Recall.call(ticket: @ticket)
      )
    end

    # "Por que a IA decidiu" (ADR 0009): a cadeia de decisão do ticket, da auditoria já gravada.
    def explanation
      render json: Tickets::Explain.call(@ticket)
    end

    # Takeover: o analista tira da IA um ticket que ainda não foi escalado.
    def takeover
      @ticket.with_lock do
        return render(status: :conflict, json: { error: "o ticket não está com a IA" }) unless @ticket.ai?

        Handoff::Escalate.call(ticket: @ticket, trigger: "analyst_takeover", reason: "analyst_takeover",
                               actor: "analyst", target: "human", assignee: current_analyst)
        Handoff::Assign.call(ticket: @ticket, analyst: current_analyst, trigger: "takeover")
      end
      render json: ticket_summary(@ticket)
    end

    def messages
      text = parse_json(request.raw_post)["text"].to_s.strip
      return render(status: :unprocessable_content, json: { error: "text é obrigatório" }) if text.empty?

      @ticket.with_lock do
        return unless owner!

        message = @ticket.append_message!(sender: "analyst", body: text)
        sla_met = record_first_response(message)
        @ticket.record_event!(kind: "message.sent", actor: "analyst",
                              data: { message_id: message.id, seq: message.seq, assignee_id: current_analyst.id,
                                      first_response: !sla_met.nil?, sla_met: sla_met }.compact)
        render status: :created, json: { message_id: message.id, seq: message.seq, sla_met: sla_met }
      end
    end

    def close
      body = parse_json(request.raw_post)
      @ticket.with_lock do
        return unless owner!

        Tickets::Close.call(ticket: @ticket, analyst: current_analyst,
                            resolution_code: body["resolution_code"], resolution_note: body["resolution_note"])
      end
      render json: ticket_summary(@ticket)
    rescue Tickets::Close::Invalid => error
      render status: :unprocessable_content, json: { error: error.message }
    end

    private

    def load_ticket
      @ticket = find_ticket
    end

    # Só o dono escreve e fecha. Ticket fechado ou sem dono responde 409; dono diferente, 403.
    def owner!
      if !@ticket.human?
        render status: :conflict, json: { error: "o ticket não está em atendimento humano" }
        false
      elsif @ticket.assignee_id != current_analyst.id
        render status: :forbidden, json: { error: "o ticket é de outro analista" }
        false
      else
        true
      end
    end

    # Na primeira mensagem humana, registra a hora e se o prazo foi cumprido. Nas seguintes, devolve nil.
    def record_first_response(message)
      return nil if @ticket.first_human_response_at

      @ticket.update!(first_human_response_at: message.created_at)
      @ticket.first_response_due_at.nil? || message.created_at <= @ticket.first_response_due_at
    end
  end
end
