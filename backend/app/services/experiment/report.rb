module Experiment
  # Resumo de uma rodada do experimento, por fase da rampa (playbook §9). Lê o ledger e o banco da própria rodada:
  # ACK do webhook (do ledger), ponta a ponta da mensagem do cliente até a resposta do agente, quantas foram
  # respondidas ou escaladas e o atraso do outbox. Percentis pelo posto mais próximo; nunca média.
  #
  # Com o mock respondendo na hora, a ponta a ponta é quase toda tempo da plataforma; com caos no agente, não.
  module Report
    WINDOW_TAIL = 60.seconds

    module_function

    def percentile(values, fraction)
      return nil if values.empty?

      sorted = values.sort
      sorted[[ (fraction * sorted.size).ceil - 1, 0 ].max]
    end

    def call(ledger:)
      seen = Set.new
      stages = ledger.group_by { |entry| entry["stage"] }.map do |stage, entries|
        fresh = entries.select { |entry| acknowledged?(entry) }.map { |entry| entry["provider_message_id"] }.uniq - seen.to_a
        seen.merge(fresh)
        summarize(stage, entries, fresh)
      end
      { stages: stages, totals: { sent: ledger.size, unique_messages: ledger.map { |entry| entry["provider_message_id"] }.uniq.size } }
    end

    def summarize(stage, entries, pmids)
      acks = entries.map { |entry| entry["ack_ms"].to_f }
      customer = Message.joins(:inbound_event).where(inbound_events: { provider_message_id: pmids }, sender: "customer")
                        .pluck(:ticket_id, :seq, :created_at)
      ticket_ids = customer.map(&:first).uniq
      replies = Message.where(ticket_id: ticket_ids, sender: "bot").pluck(:ticket_id, :seq, :created_at).group_by(&:first)
      escalated_tickets = Ticket.where(id: ticket_ids).where.not(escalated_at: nil).pluck(:id).to_set

      e2e = []
      escalated = 0
      customer.each do |ticket_id, seq, created_at|
        reply = (replies[ticket_id] || []).select { |_, reply_seq, _| reply_seq > seq }.min_by { |_, reply_seq, _| reply_seq }
        if reply
          e2e << ((reply[2] - created_at) * 1000).round
        elsif escalated_tickets.include?(ticket_id)
          escalated += 1
        end
      end
      # Só os eventos da janela da fase: o mesmo ticket (cliente tagarela) aparece em várias fases. A janela vai da
      # primeira à última mensagem da fase, mais um minuto para as escalações do vigia.
      times = customer.map(&:last)
      outbox = if times.empty?
        []
      else
        OutboxEvent.where(key: ticket_ids, created_at: times.min..(times.max + WINDOW_TAIL)).where.not(published_at: nil)
                   .pluck(:created_at, :published_at).map { |created_at, published_at| ((published_at - created_at) * 1000).round }
      end

      {
        stage: stage, sent: entries.size, redeliveries: entries.count { |entry| entry["redelivery"] },
        rate_per_s: achieved_rate(entries),
        refused: entries.count { |entry| !acknowledged?(entry) },
        ack_p50_ms: percentile(acks, 0.5), ack_p99_ms: percentile(acks, 0.99),
        answered: e2e.size, escalated: escalated,
        e2e_p50_ms: percentile(e2e, 0.5), e2e_p99_ms: percentile(e2e, 0.99),
        outbox_p99_ms: percentile(outbox, 0.99)
      }
    end

    def acknowledged?(entry) = (200..299).cover?(entry["status"].to_i)

    # Mensagens novas por segundo que o gerador conseguiu mandar na fase (sem as reentregas). Mostra quando o
    # próprio gerador não alcança a taxa pedida.
    def achieved_rate(entries)
      offsets = entries.filter_map { |entry| entry["offset_s"] }
      span = offsets.empty? ? 0 : offsets.max - offsets.min
      return nil unless span.positive?

      (entries.count { |entry| !entry["redelivery"] } / span).round(1)
    end
  end
end
