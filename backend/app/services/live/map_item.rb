module Live
  # Um ticket como o mapa vivo o desenha (ADR 0007, I12 e I13): o retrato da API e os eventos do canal usam
  # o mesmo formato.
  module MapItem
    module_function

    def call(ticket)
      {
        id: ticket.id,
        brand: ticket.brand.slug,
        channel: ticket.channel,
        mode: ticket.mode,
        priority: ticket.priority,
        queue: ticket.queue&.slug,
        tags: ticket.tags,
        cluster: cluster(ticket),
        assignee_id: ticket.assignee_id,
        created_at: ticket.created_at.iso8601(3),
        escalated_at: ticket.escalated_at&.iso8601(3),
        first_response_due_at: ticket.first_response_due_at&.iso8601(3),
        first_human_response_at: ticket.first_human_response_at&.iso8601(3),
        awaiting_agent_since: ticket.awaiting_agent_since&.iso8601(3)
      }
    end

    # Primeira tag (na ordem da regra); sem tag, a fila; sem fila, a marca (ADR 0007, I12).
    def cluster(ticket)
      if (tag = ticket.tags.first)
        { key: "tag:#{tag}", label: tag }
      elsif ticket.queue
        { key: "fila:#{ticket.queue.slug}", label: ticket.queue.slug }
      else
        { key: "marca:#{ticket.brand.slug}", label: "#{ticket.brand.name} sem fila" }
      end
    end
  end
end
