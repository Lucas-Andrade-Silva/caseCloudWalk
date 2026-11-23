module Tickets
  # Fecha os tickets que a IA resolveu (ADR 0009, W4): continuam com a IA, o agente já respondeu e o cliente não
  # escreve há `idle` (30 min por padrão, AI_IDLE_CLOSE_MINUTES). Sem isso, nada tira um ticket da IA, e eles se
  # acumulam no mapa e na memória. Se o cliente voltar, a entrada abre um ticket novo, que lembra deste.
  #
  # Idempotente: cada ticket é reavaliado sob lock.
  class AutoClose
    RESOLUTION_CODE = "ai_resolved"
    BATCH = 200

    def initialize(idle: Integer(ENV.fetch("AI_IDLE_CLOSE_MINUTES", "30")).minutes)
      @idle = idle
    end

    # Devolve quantos tickets fechou.
    def run(now: Time.current)
      limit = now - @idle
      candidates = Ticket.where(mode: "ai", awaiting_agent_since: nil)
                         .where(created_at: ...limit)
                         .where.not(Message.where(sender: "customer", created_at: limit..)
                                           .where("messages.ticket_id = tickets.id").arel.exists)
                         .order(:created_at).limit(BATCH).pluck(:id)

      candidates.count { |id| close_if_still_idle(id, limit, now) }
    end

    private

    def close_if_still_idle(id, limit, now)
      ticket = Ticket.find(id)
      ticket.with_lock do
        last_customer = ticket.messages.where(sender: "customer").maximum(:created_at)
        next false unless ticket.ai? && ticket.awaiting_agent_since.nil? && (last_customer.nil? || last_customer < limit)

        ticket.transition_to!("closed", closed_at: now, resolution_code: RESOLUTION_CODE)
        ticket.record_event!(kind: "ticket.closed", actor: "system",
                             data: { resolution_code: RESOLUTION_CODE, idle_minutes: (@idle / 60).to_i })
        ClosingSummary.create!(
          ticket: ticket, brand_id: ticket.brand_id, customer_id: ticket.customer_id,
          version: Memory::ClosingSummaryTemplate::VERSION, source: Memory::ClosingSummaryTemplate::SOURCE,
          text: Memory::ClosingSummaryTemplate.build(ticket), expires_at: now + Memory.window_days.days
        )
        Llm::Summaries.enqueue_after_commit(ClosingSummaryJob, ticket.id)
        true
      end
    end
  end
end
