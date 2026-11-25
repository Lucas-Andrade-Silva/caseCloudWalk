module Dashboard
  # Detalhe do card "Desempenho do time" (ADR 0011): o time inteiro nos últimos 7 dias, com totais, uma linha por
  # analista (recebidos, respondidos, resolvidos, em atendimento, resposta, SLA, tempo de solução e assunto
  # principal), os assuntos mais tratados e a série diária. Só números, nunca as conversas.
  # O analista vê os colegas que atendem ao menos uma marca dele, com os tickets dessas marcas; a operação vê todos.
  class TeamDetail < Report
    SUBJECTS_LIMIT = 5

    def call
      header.merge(totals: summary(received, resolved, open_count, messages_sent), agents: agents, subjects: subjects, daily: daily)
    end

    private

    def analysts
      @analysts ||= begin
        scope = User.where(role: "analyst")
        scope = scope.joins(:queues).where(queues: { brand_id: @brand_ids }).distinct if @brand_ids
        scope.order(:name).to_a
      end
    end

    def ids = analysts.map(&:id)

    # [assignee_id, escalated_at, first_human_response_at, first_response_due_at, llm_facts] dos recebidos na janela.
    def received
      @received ||= tickets.where(assignee_id: ids, escalated_at: window)
                           .pluck(:assignee_id, :escalated_at, :first_human_response_at, :first_response_due_at, :llm_facts)
    end

    # [assignee_id, created_at, closed_at] dos resolvidos por humano na janela.
    def resolved
      @resolved ||= tickets.where(assignee_id: ids, closed_at: window).where.not(resolution_code: [ nil, Tickets::AutoClose::RESOLUTION_CODE ])
                           .pluck(:assignee_id, :created_at, :closed_at)
    end

    def open_by_agent = @open_by_agent ||= tickets.where(assignee_id: ids, mode: "human").group(:assignee_id).count

    def messages_by_agent
      @messages_by_agent ||= Message.where(sender: "analyst", created_at: window).joins(:ticket)
                                    .merge(tickets.where(assignee_id: ids)).group("tickets.assignee_id").count
    end

    def open_count = open_by_agent.values.sum
    def messages_sent = messages_by_agent.values.sum

    def summary(received_rows, resolved_rows, open, messages)
      answered = received_rows.select { |row| row[2] }
      with_due = answered.select { |row| row[3] }
      met = with_due.count { |_, _, replied, due, _| replied <= due }
      {
        received: received_rows.size, answered: answered.size, resolved: resolved_rows.size, open: open, messages_sent: messages,
        first_reply_mean_seconds: mean(answered.map { |_, escalated, replied, _, _| (replied - escalated).round }),
        sla_percent: percent(met, with_due.size),
        solution_mean_seconds: mean(resolved_rows.map { |_, created, closed| (closed - created.in_time_zone("UTC")).round })
      }
    end

    def agents
      slugs = Brand.pluck(:id, :slug).to_h
      rows = analysts.map do |agent|
        mine = received.select { |row| row[0] == agent.id }
        stats = summary(mine, resolved.select { |row| row[0] == agent.id }, open_by_agent.fetch(agent.id, 0), 0).except(:messages_sent)
        brand_ids = @brand_ids ? agent.brand_ids & @brand_ids : agent.brand_ids
        { id: agent.id, name: agent.name, brands: brand_ids.filter_map { |id| slugs[id] }.sort }
          .merge(stats).merge(top_subject: top_subject(mine))
      end
      rows.sort_by { |row| [ -row[:resolved], row[:name] ] }
    end

    def top_subject(rows)
      rows.filter_map { |row| row[4]["category"].presence }.tally.min_by { |category, count| [ -count, category ] }&.first
    end

    def subjects
      received.map { |row| row[4]["category"].presence }.tally.sort_by { |category, count| [ -count, category.to_s ] }
              .first(SUBJECTS_LIMIT).map { |category, count| { category: category, count: count } }
    end

    def daily
      received_by_day = received.map { |row| local_date(row[1]) }.tally
      resolved_by_day = resolved.map { |row| local_date(row[2]) }.tally
      window_dates.map { |date| { date: date.iso8601, received: received_by_day.fetch(date, 0), resolved: resolved_by_day.fetch(date, 0) } }
    end
  end
end
