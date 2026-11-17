module Api
  # Trabalho do analista: o que é dele e o que espera nas filas dele. Quem escolhe o próximo é a
  # plataforma, pelo prazo mais próximo (ADR 0004, H4); a lista de espera é só para ver.
  class WorkController < AnalystController
    WAITING_LIMIT = 50

    def index
      waiting = Handoff::AssignNext.waiting_for(current_analyst)
      mine = Ticket.where(mode: "human", assignee_id: current_analyst.id)
                   .order(Arel.sql("first_response_due_at ASC NULLS LAST"), :escalated_at, :id)

      render json: {
        mine: list(mine),
        waiting: list(waiting.limit(WAITING_LIMIT)),
        waiting_count: waiting.count
      }
    end

    def next
      ticket = Handoff::AssignNext.call(analyst: current_analyst)
      return head :no_content unless ticket

      render json: ticket_summary(ticket)
    end

    private

    def list(scope)
      tickets = scope.includes(:brand, :queue, :customer).to_a
      last_messages = Message.where(ticket_id: tickets.map(&:id))
                             .select("DISTINCT ON (ticket_id) ticket_id, sender, body, created_at")
                             .order(:ticket_id, seq: :desc)
                             .index_by(&:ticket_id)

      tickets.map do |ticket|
        last = last_messages[ticket.id]
        {
          id: ticket.id,
          brand: ticket.brand.slug,
          channel: ticket.channel,
          mode: ticket.mode,
          priority: ticket.priority,
          queue: ticket.queue&.slug,
          tags: ticket.tags,
          customer: { external_id: ticket.customer.external_id, name: ticket.customer.name },
          escalated_at: ticket.escalated_at&.iso8601(3),
          first_response_due_at: ticket.first_response_due_at&.iso8601(3),
          first_human_response_at: ticket.first_human_response_at&.iso8601(3),
          last_message: last && { sender: last.sender, text: last.body, created_at: last.created_at.iso8601(3) }
        }
      end
    end
  end
end
