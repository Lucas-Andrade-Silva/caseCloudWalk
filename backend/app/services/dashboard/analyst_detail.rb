module Dashboard
  # Detalhe de um analista (ADR 0011): o que ele recebeu, respondeu e resolveu na janela, o SLA da primeira
  # resposta, os assuntos que mais trata e a série diária. Só números: nunca o texto das conversas dele.
  # Os tickets contados são os das marcas de quem pergunta, então um colega só aparece pelas marcas em comum.
  class AnalystDetail < Report
    SUBJECTS_LIMIT = 5

    def initialize(agent:, **options)
      super(**options)
      @agent = agent
    end

    def call
      header.merge(
        agent: { id: @agent.id, name: @agent.name, brands: agent_brands },
        open: own.where(mode: "human").count,
        received: received.count,
        answered: answered.size,
        resolved: resolved.size,
        messages_sent: Message.where(sender: "analyst", created_at: window, ticket_id: own.select(:id)).count,
        first_reply: { mean_seconds: mean(reply_seconds), answered: answered.size },
        sla: sla,
        resolution_time: { mean_seconds: mean(solution_seconds), median_seconds: median(solution_seconds), resolved: resolved.size },
        subjects: subjects,
        brands: brands,
        daily: daily
      )
    end

    private

    def own = tickets.where(assignee_id: @agent.id)

    def received = own.where(escalated_at: window)

    def agent_brands
      ids = @brand_ids ? @agent.brand_ids & @brand_ids : @agent.brand_ids
      Brand.where(id: ids).order(:slug).pluck(:slug)
    end

    # [escalated_at, first_human_response_at, first_response_due_at] dos recebidos que já foram respondidos.
    def answered
      @answered ||= received.where.not(first_human_response_at: nil).pluck(:escalated_at, :first_human_response_at, :first_response_due_at)
    end

    def reply_seconds = answered.map { |escalated, replied, _| (replied - escalated).round }

    def sla
      with_due = answered.select { |_, _, due| due }
      met = with_due.count { |_, replied, due| replied <= due }
      { met: met, missed: with_due.size - met, percent: percent(met, with_due.size) }
    end

    # Resolvidos por humano na janela (o fechamento automático da IA não é do analista).
    def resolved
      @resolved ||= own.where(closed_at: window).where.not(resolution_code: [ nil, Tickets::AutoClose::RESOLUTION_CODE ])
                       .pluck(:created_at, :closed_at, :id)
    end

    def solution_seconds = resolved.map { |created, closed, _| (closed - created.in_time_zone("UTC")).round }

    def subjects
      received.pluck(:llm_facts).map { |facts| facts["category"].presence }.tally
              .sort_by { |category, count| [ -count, category.to_s ] }.first(SUBJECTS_LIMIT)
              .map { |category, count| { category: category, count: count } }
    end

    def brands
      received.joins(:brand).group("brands.slug").count.sort_by { |slug, count| [ -count, slug ] }
              .map { |slug, count| { brand: slug, count: count } }
    end

    def daily
      received_by_day = received.pluck(:escalated_at).map { |time| local_date(time) }.tally
      resolved_by_day = resolved.map { |_, closed, _| local_date(closed) }.tally
      window_dates.map { |date| { date: date.iso8601, received: received_by_day.fetch(date, 0), resolved: resolved_by_day.fetch(date, 0) } }
    end
  end
end
