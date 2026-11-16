module Handoff
  # Tira o ticket da IA e o põe na fila humana: modo, fila, prazo de SLA, brief, linha do tempo e aviso
  # ao agente, tudo na transação de quem chama. Quem chama segura o lock do ticket.
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
      queue = TicketQueue.default_for(@ticket.brand) or
        raise NoDefaultQueue, "a marca #{@ticket.brand.slug} não tem fila padrão"
      level = PriorityLevel.find(@ticket.priority)
      brief = Brief.build(ticket: @ticket, trigger: @trigger, reason: @reason, now: now)

      @ticket.transition_to!(
        @target,
        queue: queue,
        assignee: @assignee,
        escalation_trigger: @trigger,
        escalation_reason: @reason,
        escalated_at: now,
        first_response_due_at: level.first_response_deadline(now),
        handoff_brief: brief,
        awaiting_agent_since: nil
      )

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
