module Handoff
  # Tira o ticket da IA e o põe na fila humana: modo, fila, prazo de SLA, brief, linha do tempo e aviso
  # ao agente, tudo na transação de quem chama. Quem chama segura o lock do ticket.
  #
  # A fila e a prioridade vêm das regras, reavaliadas com os fatos de escalação. Sem regra: fila prevista
  # na abertura; sem ela, a fila padrão da marca (ADR 0005, R2).
  #
  # `target` é "pending_human" (espera um analista puxar) ou "human" (takeover: já tem dono).
  class Escalate
    class NoDefaultQueue < StandardError; end

    def self.call(...) = new(...).call

    def initialize(ticket:, trigger:, reason:, actor:, target: "pending_human", assignee: nil, data: {})
      @ticket = ticket
      @trigger = trigger
      @reason = reason
      @actor = actor
      @target = target
      @assignee = assignee
      @data = data
    end

    def call
      now = Time.current
      facts = Rules::Facts.for_escalation(@ticket, trigger: @trigger, reason: @reason, now: now)
      outcome = Rules::Router.evaluate(brand: @ticket.brand, facts: facts)
      queue = outcome.queue || @ticket.queue || TicketQueue.default_for(@ticket.brand) or
        raise NoDefaultQueue, "a marca #{@ticket.brand.slug} não tem fila padrão"
      priority = outcome.priority || @ticket.priority
      level = PriorityLevel.find(priority)
      brief = Brief.build(ticket: @ticket, trigger: @trigger, reason: @reason, now: now)

      @ticket.transition_to!(
        @target,
        queue: queue,
        priority: priority,
        tags: @ticket.tags | outcome.tags,
        assignee: @assignee,
        escalation_trigger: @trigger,
        escalation_reason: @reason,
        escalated_at: now,
        first_response_due_at: level.first_response_deadline(now),
        handoff_brief: brief,
        awaiting_agent_since: nil
      )

      Rules::Router.record!(ticket: @ticket, step: "routing.escalation", facts: facts, outcome: outcome)
      @ticket.record_event!(kind: "ticket.escalated", actor: @actor, data: event_data(queue))
      AgentEvents.ticket_escalated!(ticket: @ticket)
      @ticket
    end

    private

    def event_data(queue)
      {
        trigger: @trigger,
        reason: @reason,
        queue_id: queue.id,
        priority: @ticket.priority,
        handoff_epoch: @ticket.handoff_epoch,
        first_response_due_at: @ticket.first_response_due_at.iso8601(3)
      }.merge(@data)
    end
  end
end
