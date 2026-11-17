module Handoff
  # Dá o ticket a um analista e registra quanto tempo ele esperou. Quem chama segura o lock do ticket.
  module Assign
    module_function

    def call(ticket:, analyst:, trigger:)
      ticket.transition_to!("human", assignee: analyst) unless ticket.human?
      waited = ticket.escalated_at ? (Time.current - ticket.escalated_at).round : 0
      ticket.record_event!(kind: "ticket.assigned", actor: "analyst",
                           data: { trigger: trigger, assignee_id: analyst.id, waited_seconds: waited })
      ticket
    end
  end
end
