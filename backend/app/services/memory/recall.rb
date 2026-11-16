module Memory
  # O que a plataforma lembra do cliente ao atender um ticket (ADR 0006, M1): os tickets mais recentes dele na
  # mesma marca, de qualquer canal, dentro da janela e depois da última exclusão, sem o próprio ticket.
  class Recall
    LIMIT = 5

    def self.call(...) = new(...).call

    def initialize(ticket:, now: Time.current, window_days: Memory.window_days)
      @ticket = ticket
      @now = now
      @window_days = window_days
    end

    def call
      { window_days: @window_days, tickets: previous_tickets.map { |ticket| item(ticket) } }
    end

    private

    def previous_tickets
      since = [ @now - @window_days.days, @ticket.customer.memory_erased_at ].compact.max
      Ticket.where(brand_id: @ticket.brand_id, customer_id: @ticket.customer_id)
            .where.not(id: @ticket.id)
            .where("tickets.created_at >= ?", since)
            .includes(:queue, :closing_summary)
            .order(created_at: :desc).limit(LIMIT)
    end

    def item(ticket)
      summary = ticket.closing_summary
      {
        ticket_id: ticket.id,
        channel: ticket.channel,
        mode: ticket.mode,
        opened_at: ticket.created_at.iso8601(3),
        closed_at: ticket.closed_at&.iso8601(3),
        priority: ticket.priority,
        queue: ticket.queue&.slug,
        tags: ticket.tags,
        escalation_reason: ticket.escalation_reason,
        resolution_code: ticket.resolution_code,
        summary: summary && summary.expires_at > @now ? summary.text : nil
      }
    end
  end
end
