module Dashboard
  # Números do Painel, todos lidos do banco (nada estimado): o que está aberto agora, criados e resolvidos hoje
  # contra ontem, a série diária, a primeira resposta humana, o SLA, quem resolveu e os canais. "Hoje" segue o
  # fuso da operação (DASHBOARD_TIME_ZONE, padrão America/Sao_Paulo). A janela é de 7 dias, contando hoje.
  class Metrics < Report
    # Faixas da primeira resposta humana, em segundos (limite superior inclusivo).
    BUCKETS = [ [ "up_to_5m", 5 * 60 ], [ "5m_to_15m", 15 * 60 ], [ "15m_to_1h", 60 * 60 ], [ "over_1h", Float::INFINITY ] ].freeze

    def call
      {
        generated_at: @now.iso8601(3),
        time_zone: @zone.tzinfo.name,
        open: open_now,
        today: created_and_closed(@today..@now),
        yesterday: created_and_closed((@today - 1.day)...@today),
        daily: daily,
        first_reply: first_reply,
        sla: sla,
        resolution: resolution,
        resolution_time: resolution_time,
        team: team,
        operations: operations,
        channels: tickets.where(created_at: @window_start..@now).group(:channel).count
                         .map { |channel, count| { channel: channel, count: count } }
      }
    end

    private

    def open_now
      by_mode = tickets.open.group(:mode).count
      incidents = @brand_ids ? Incident.open.where(brand_id: @brand_ids) : Incident.open
      { total: by_mode.values.sum, ai: by_mode.fetch("ai", 0), pending_human: by_mode.fetch("pending_human", 0),
        human: by_mode.fetch("human", 0), incidents: incidents.count }
    end

    def created_and_closed(range)
      { created: tickets.where(created_at: range).count, closed: tickets.where(closed_at: range).count }
    end

    # created_at é UTC sem fuso; closed_at tem fuso. As duas viram data local da operação.
    def daily
      tz = ApplicationRecord.connection.quote(@zone.tzinfo.name)
      created = tickets.where(created_at: @window_start..@now)
                       .group(Arel.sql("date(timezone(#{tz}, tickets.created_at AT TIME ZONE 'UTC'))")).count
      closed = tickets.where(closed_at: @window_start..@now)
                      .group(Arel.sql("date(timezone(#{tz}, tickets.closed_at))")).count
      (0...DAYS).map do |offset|
        date = (@window_start + offset.days).to_date
        { date: date.iso8601, created: created.fetch(date, 0), closed: closed.fetch(date, 0) }
      end
    end

    def escalated = tickets.where(escalated_at: @window_start..@now)

    def first_reply
      rows = escalated.pluck(:escalated_at, :first_human_response_at)
      seconds = rows.filter_map { |escalated_at, answered_at| answered_at && (answered_at - escalated_at).round }.sort
      buckets = BUCKETS.each_with_index.map do |(key, upper), index|
        lower = index.zero? ? -Float::INFINITY : BUCKETS[index - 1][1]
        { key: key, count: seconds.count { |value| value > lower && value <= upper } }
      end
      { mean_seconds: mean(seconds), answered: seconds.size,
        buckets: buckets << { key: "waiting", count: rows.count { |_, answered_at| answered_at.nil? } } }
    end

    def sla
      met = missed = 0
      escalated.where.not(first_response_due_at: nil).pluck(:first_response_due_at, :first_human_response_at).each do |due, answered_at|
        if answered_at
          answered_at <= due ? met += 1 : missed += 1
        elsif due < @now
          missed += 1
        end
      end
      { met: met, missed: missed }
    end

    def resolution
      codes = tickets.where(closed_at: @window_start..@now).where.not(resolution_code: nil).group(:resolution_code).count
      ai = codes.fetch(Tickets::AutoClose::RESOLUTION_CODE, 0)
      { ai: ai, human: codes.values.sum - ai }
    end

    # Tempo de solução: da abertura ao fechamento, dos tickets fechados na janela.
    def resolution_time
      rows = tickets.where(closed_at: @window_start..@now).where.not(resolution_code: nil)
                    .pluck(:created_at, :closed_at, :resolution_code)
      seconds = ->(list) { median(list.map { |created, closed, _| (closed - created.in_time_zone("UTC")).round }.sort) }
      ai, human = rows.partition { |_, _, code| code == Tickets::AutoClose::RESOLUTION_CODE }
      { median_seconds: seconds.(rows), ai_median_seconds: seconds.(ai), human_median_seconds: seconds.(human),
        resolved: rows.size }
    end

    # Desempenho por analista. Não há CSAT na plataforma: a coluna de qualidade é o SLA da primeira resposta.
    def team
      agents = User.where(role: "analyst")
      agents = agents.joins(:queues).where(queues: { brand_id: @brand_ids }).distinct if @brand_ids
      rows = agents.order(:name).map { |agent| agent_row(agent) }
                   .sort_by { |row| [ -row[:resolved], row[:name] ] }
      { active: rows.count { |row| row[:open].positive? }, total: rows.size, agents: rows }
    end

    def agent_row(agent)
      own = tickets.where(assignee_id: agent.id)
      answered = own.where(escalated_at: @window_start..@now).where.not(first_human_response_at: nil)
                    .pluck(:escalated_at, :first_human_response_at, :first_response_due_at)
      replies = answered.map { |escalated, replied, _| (replied - escalated).round }.sort
      with_due = answered.select { |_, _, due| due }
      {
        id: agent.id, name: agent.name,
        resolved: own.where(closed_at: @window_start..@now).where.not(resolution_code: [ nil, Tickets::AutoClose::RESOLUTION_CODE ]).count,
        open: own.where(mode: "human").count,
        reply_median_seconds: median(replies),
        sla_percent: with_due.empty? ? nil : (with_due.count { |_, replied, due| replied <= due } * 100.0 / with_due.size).round
      }
    end

    STALE_AFTER = 3.days
    OPERATIONS_LIMIT = 6

    # Operação dos tickets: parados há mais de 3 dias, esperando humano sem analista e os que pedem gente agora.
    def operations
      open = tickets.open
      attention = open.where(mode: %w[pending_human human]).includes(:assignee, :brand)
                      .order(:priority, :escalated_at).limit(OPERATIONS_LIMIT).to_a
      subjects = Message.where(ticket_id: attention.map(&:id), sender: "customer").order(:seq)
                        .pluck(:ticket_id, :body).to_h
      {
        stale: open.where(created_at: ...(@now - STALE_AFTER)).count,
        unassigned: open.where(mode: "pending_human", assignee_id: nil).count,
        tickets: attention.map do |ticket|
          { id: ticket.id, agent: ticket.assignee&.name, agent_id: ticket.assignee_id, priority: ticket.priority, brand: ticket.brand.slug,
            mode: ticket.mode, subject: (ticket.llm_facts["summary"].presence || subjects[ticket.id]).to_s.truncate(90) }
        end
      }
    end
  end
end
