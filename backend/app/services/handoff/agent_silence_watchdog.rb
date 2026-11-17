module Handoff
  # Escala os tickets em que o cliente espera o agente há mais tempo que o limite (30 s por padrão).
  # Com o ciclo de 5 s do Sidekiq, a escalação chega em até ~40 s (ADR 0004, H6).
  #
  # Idempotente: cada ticket é reavaliado sob lock, e um ticket que já saiu da IA não muda.
  class AgentSilenceWatchdog
    BATCH = 100

    def initialize(timeout:)
      @timeout = timeout
    end

    # Devolve quantos tickets escalou.
    def run
      limit = Time.current - @timeout
      candidates = Ticket.where(mode: "ai").where(awaiting_agent_since: ...limit)
                         .order(:awaiting_agent_since).limit(BATCH).pluck(:id)

      candidates.count { |id| escalate_if_still_silent(id, limit) }
    end

    private

    def escalate_if_still_silent(id, limit)
      ticket = Ticket.find(id)
      ticket.with_lock do
        next false unless ticket.ai? && ticket.awaiting_agent_since && ticket.awaiting_agent_since < limit

        waited = (Time.current - ticket.awaiting_agent_since).round
        Escalate.call(ticket: ticket, trigger: "agent_timeout", reason: "agent_silence", actor: "system",
                      data: { waited_seconds: waited })
        true
      end
    end
  end
end
