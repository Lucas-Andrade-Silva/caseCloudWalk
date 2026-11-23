module Dashboard
  # Números do Painel, todos lidos do banco (nada estimado): o que está aberto agora, criados e resolvidos hoje
  # contra ontem, a série diária, a primeira resposta humana, o SLA, quem resolveu e os canais. "Hoje" segue o
  # fuso da operação (DASHBOARD_TIME_ZONE, padrão America/Sao_Paulo). A janela é de 7 dias, contando hoje.
  class Metrics
    DAYS = 7
    # Faixas da primeira resposta humana, em segundos (limite superior inclusivo).
    BUCKETS = [ [ "up_to_5m", 5 * 60 ], [ "5m_to_15m", 15 * 60 ], [ "15m_to_1h", 60 * 60 ], [ "over_1h", Float::INFINITY ] ].freeze

    def self.call(...) = new(...).call

    def initialize(brand_ids:, now: Time.current, zone: ENV.fetch("DASHBOARD_TIME_ZONE", "America/Sao_Paulo"))
      @brand_ids = brand_ids
      @now = now
      @zone = ActiveSupport::TimeZone[zone] || ActiveSupport::TimeZone["UTC"]
      @today = @now.in_time_zone(@zone).beginning_of_day
      @window_start = @today - (DAYS - 1).days
    end

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
        channels: tickets.where(created_at: @window_start..@now).group(:channel).count
                         .map { |channel, count| { channel: channel, count: count } }
      }
    end

    private

    def tickets = @brand_ids ? Ticket.where(brand_id: @brand_ids) : Ticket.all

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
      { median_seconds: median(seconds), answered: seconds.size,
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

    def median(sorted)
      return nil if sorted.empty?

      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0).round
    end
  end
end
