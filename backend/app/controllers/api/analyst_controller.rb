module Api
  # Base das rotas do analista humano. Autentica pelo token e restringe às marcas que ele atende.
  class AnalystController < ApplicationController
    include TokenAuthentication
    include JsonBody

    authenticate_roles "analyst", forbidden: "apenas analistas"

    rescue_from Ticket::InvalidTransition, with: -> { render status: :conflict, json: { error: "transição inválida" } }

    private

    def current_analyst = current_user

    # Ticket de uma marca que o analista atende. Os de outras marcas respondem 404, sem dizer que existem.
    def find_ticket
      Ticket.where(brand_id: current_analyst.brand_ids).find_by(id: params[:id]) ||
        (render(status: :not_found, json: { error: "ticket não encontrado" }) && nil)
    end

    def ticket_summary(ticket)
      {
        id: ticket.id,
        mode: ticket.mode,
        brand: ticket.brand.slug,
        channel: ticket.channel,
        queue: ticket.queue&.slug,
        priority: ticket.priority,
        tags: ticket.tags,
        customer: { external_id: ticket.customer.external_id, name: ticket.customer.name },
        assignee_id: ticket.assignee_id,
        handoff_epoch: ticket.handoff_epoch,
        escalated_at: ticket.escalated_at&.iso8601(3),
        first_response_due_at: ticket.first_response_due_at&.iso8601(3),
        first_human_response_at: ticket.first_human_response_at&.iso8601(3),
        llm_facts: ticket.llm_facts,
        closed_at: ticket.closed_at&.iso8601(3),
        resolution_code: ticket.resolution_code,
        handoff_brief: ticket.handoff_brief
      }
    end
  end
end
