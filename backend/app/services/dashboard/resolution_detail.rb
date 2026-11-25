module Dashboard
  # Detalhe do tempo de solução (ADR 0011): da abertura ao fechamento dos tickets fechados na janela. Mostra
  # média e mediana, quanto cabe na meta, a distribuição, IA contra humano, marcas, assuntos, a série diária e
  # os tickets mais lentos.
  class ResolutionDetail < Report
    TARGET = 8.hours
    LIST_LIMIT = 5
    # Faixas do tempo de solução, em segundos (limite superior inclusivo).
    BUCKETS = [ [ "up_to_15m", 15.minutes ], [ "15m_to_1h", 1.hour ], [ "1h_to_8h", 8.hours ], [ "8h_to_24h", 24.hours ],
                [ "over_24h", Float::INFINITY ] ].freeze

    Row = Struct.new(:ticket, :seconds, :ai, :category, :closed_on)

    def call
      header.merge(
        target_seconds: TARGET.to_i,
        resolved: rows.size,
        median_seconds: median(seconds),
        mean_seconds: mean(seconds),
        within_target_percent: percent(seconds.count { |value| value <= TARGET }, rows.size),
        by_resolver: { ai: summary(rows.select(&:ai)), human: summary(rows.reject(&:ai)) },
        buckets: BUCKETS.each_with_index.map { |(key, upper), index| { key: key, count: seconds.count { |value| in_bucket?(value, index, upper) } } },
        brands: brands,
        categories: categories,
        slowest: slowest,
        daily: daily
      )
    end

    private

    def seconds = rows.map(&:seconds)

    def rows
      @rows ||= tickets.where(closed_at: window).where.not(resolution_code: nil).includes(:brand, :assignee).map do |ticket|
        Row.new(ticket, (ticket.closed_at - ticket.created_at).round, ticket.resolution_code == Tickets::AutoClose::RESOLUTION_CODE,
                ticket.llm_facts["category"].presence, local_date(ticket.closed_at))
      end
    end

    def in_bucket?(value, index, upper)
      lower = index.zero? ? -Float::INFINITY : BUCKETS[index - 1][1]
      value > lower && value <= upper
    end

    def summary(list) = { count: list.size, median_seconds: median(list.map(&:seconds)), mean_seconds: mean(list.map(&:seconds)) }

    def brands
      rows.group_by { |row| row.ticket.brand.slug }.sort_by { |slug, list| [ -list.size, slug ] }
          .map { |slug, list| { brand: slug, resolved: list.size, median_seconds: median(list.map(&:seconds)) } }
    end

    def categories
      rows.group_by(&:category).sort_by { |category, list| [ -list.size, category.to_s ] }.first(LIST_LIMIT)
          .map { |category, list| { category: category, resolved: list.size, median_seconds: median(list.map(&:seconds)) } }
    end

    def slowest
      rows.sort_by { |row| -row.seconds }.first(LIST_LIMIT).map do |row|
        { id: row.ticket.id, brand: row.ticket.brand.slug, category: row.category, seconds: row.seconds,
          resolved_by: row.ai ? "ai" : "human", agent: row.ticket.assignee&.name }
      end
    end

    def daily
      by_day = rows.group_by(&:closed_on)
      window_dates.map do |date|
        list = by_day.fetch(date, [])
        { date: date.iso8601, resolved: list.size, median_seconds: median(list.map(&:seconds)) }
      end
    end
  end
end
