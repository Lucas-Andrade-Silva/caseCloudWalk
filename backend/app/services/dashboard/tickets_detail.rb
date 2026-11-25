module Dashboard
  # Detalhe do card "Operação dos tickets" (ADR 0011): todos os tickets que pedem gente agora (esperando humano ou
  # com humano), com prioridade, quem está com eles, há quanto tempo esperam e o prazo da primeira resposta, e os
  # tickets abertos há mais de 3 dias. Escopo de marcas como o do Painel.
  class TicketsDetail < Report
    ATTENTION_LIMIT = 100
    STALE_LIMIT = 20
    STALE_AFTER = 3.days
    SUBJECT_LENGTH = 90
    PRIORITIES = %w[p1 p2 p3 p4].freeze

    def call
      header.merge(counts: counts, tickets: attention_rows, stale_tickets: stale_rows)
    end

    private

    def open_tickets = tickets.open

    def attention = open_tickets.where(mode: %w[pending_human human])

    def stale = open_tickets.where(created_at: ...(@now - STALE_AFTER))

    def overdue?(ticket) = ticket.first_response_due_at.present? && ticket.first_human_response_at.nil? && ticket.first_response_due_at < @now

    def counts
      by_priority = attention.group(:priority).count
      {
        attention: attention.count,
        unassigned: open_tickets.where(mode: "pending_human", assignee_id: nil).count,
        overdue: attention.where(first_human_response_at: nil).where(first_response_due_at: ...@now).count,
        stale: stale.count,
        by_priority: PRIORITIES.index_with { |priority| by_priority.fetch(priority, 0) },
        by_brand: attention.joins(:brand).group("brands.slug").count.sort_by { |slug, count| [ -count, slug ] }
                           .map { |slug, count| { brand: slug, count: count } }
      }
    end

    def subjects_for(list)
      Message.where(ticket_id: list.map(&:id), sender: "customer").order(:seq).pluck(:ticket_id, :body).to_h
    end

    def subject(ticket, messages) = (ticket.llm_facts["summary"].presence || messages[ticket.id]).to_s.truncate(SUBJECT_LENGTH)

    def attention_rows
      list = attention.includes(:assignee, :brand).order(:priority, :escalated_at).limit(ATTENTION_LIMIT).to_a
      messages = subjects_for(list)
      list.map do |ticket|
        {
          id: ticket.id, brand: ticket.brand.slug, priority: ticket.priority, mode: ticket.mode,
          agent: ticket.assignee&.name, agent_id: ticket.assignee_id,
          category: ticket.llm_facts["category"].presence, subject: subject(ticket, messages),
          waiting_seconds: ticket.escalated_at && (@now - ticket.escalated_at).round,
          first_response_due_at: ticket.first_response_due_at&.iso8601(3),
          first_human_response_at: ticket.first_human_response_at&.iso8601(3),
          overdue: overdue?(ticket)
        }
      end
    end

    def stale_rows
      list = stale.includes(:assignee, :brand).order(:created_at).limit(STALE_LIMIT).to_a
      messages = subjects_for(list)
      list.map do |ticket|
        {
          id: ticket.id, brand: ticket.brand.slug, priority: ticket.priority, mode: ticket.mode,
          agent: ticket.assignee&.name, agent_id: ticket.assignee_id, subject: subject(ticket, messages),
          age_seconds: (@now - ticket.created_at).round
        }
      end
    end
  end
end
