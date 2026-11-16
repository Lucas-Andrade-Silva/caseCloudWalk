module Invariants
  # Confere os quatro invariantes do playbook (§3.7) para as mensagens de um ledger de carga.
  #
  #   1. Zero perda: toda mensagem do ledger entrou e foi respondida ou saiu da IA (escalada).
  #   2. Zero duplicata visível: no máximo uma resposta do bot por (ticket, in_reply_to_seq).
  #   3. Ordem: seq contínuo por ticket e horário crescente com o seq.
  #   4. Sem órfãos: nenhum ticket esquecido com a IA além de `orphan_after` e nenhum escalado sem fila.
  #
  # Rode depois que o fluxo esvaziar: uma mensagem ainda a caminho conta como perda.
  #
  # Só cobra o que a plataforma confirmou: entrada do ledger com `status` que não é 2xx (503, timeout) é
  # responsabilidade de quem envia, que deve reenviar. Entrada sem `status` conta como confirmada.
  class Checker
    def self.call(...) = new(...).call

    def initialize(ledger:, orphan_after: 60, now: Time.current)
      @ledger = ledger
      @orphan_after = orphan_after
      @now = now
    end

    def call
      acknowledged, refused = @ledger.partition { |entry| acknowledged?(entry) }
      pairs = acknowledged.map { |entry| [ entry.fetch("channel"), entry.fetch("provider_message_id") ] }.uniq
      not_acknowledged = (refused.map { |entry| [ entry["channel"], entry["provider_message_id"] ] }.uniq - pairs).size
      inbound_ids = inbound_ids_for(pairs)
      messages = Message.where(inbound_event_id: inbound_ids.values)
                        .pluck(:inbound_event_id, :ticket_id, :seq).to_h { |inbound, ticket, seq| [ inbound, [ ticket, seq ] ] }
      ticket_ids = messages.values.map(&:first).uniq
      modes = Ticket.where(id: ticket_ids).pluck(:id, :mode).to_h
      answered_through = Message.where(ticket_id: ticket_ids, sender: "bot").group(:ticket_id).maximum(:in_reply_to_seq)

      counts = Hash.new(0)
      lost = []
      pairs.each do |channel, provider_id|
        inbound_id = inbound_ids[[ channel, provider_id ]]
        next lost << loss(channel, provider_id, "not_ingested") unless inbound_id

        ticket_id, seq = messages.fetch(inbound_id)
        counts[:ingested] += 1
        if answered_through[ticket_id].to_i >= seq
          counts[:answered] += 1
        elsif modes[ticket_id] != "ai"
          counts[:escalated] += 1
        else
          lost << loss(channel, provider_id, "unanswered").merge(ticket_id: ticket_id, seq: seq)
        end
      end

      violations = { lost: lost, duplicates: duplicates(ticket_ids), order: order(ticket_ids), orphans: orphans(ticket_ids) }
      {
        ok: violations.values.all?(&:empty?),
        ledger_entries: @ledger.size,
        unique_messages: pairs.size,
        not_acknowledged: not_acknowledged,
        ingested: counts[:ingested],
        answered: counts[:answered],
        escalated: counts[:escalated],
        violations: violations
      }
    end

    private

    def acknowledged?(entry)
      !entry.key?("status") || (200..299).cover?(Integer(entry["status"].to_s, exception: false).to_i)
    end

    def loss(channel, provider_id, reason) = { channel: channel, provider_message_id: provider_id, reason: reason }

    def inbound_ids_for(pairs)
      pairs.group_by(&:first).each_with_object({}) do |(channel, channel_pairs), found|
        InboundEvent.where(channel: channel, provider_message_id: channel_pairs.map(&:last))
                    .pluck(:provider_message_id, :id)
                    .each { |provider_id, id| found[[ channel, provider_id ]] = id }
      end
    end

    def duplicates(ticket_ids)
      Message.where(ticket_id: ticket_ids, sender: "bot").where.not(in_reply_to_seq: nil)
             .group(:ticket_id, :in_reply_to_seq).having("count(*) > 1").count
             .map { |(ticket_id, seq), count| { ticket_id: ticket_id, in_reply_to_seq: seq, count: count } }
    end

    def order(ticket_ids)
      gaps = Message.where(ticket_id: ticket_ids).group(:ticket_id)
                    .pluck(:ticket_id, Arel.sql("count(*)"), Arel.sql("min(seq)"), Arel.sql("max(seq)"))
                    .reject { |_, count, min, max| min == 1 && max == count }
                    .map { |ticket_id, *| { ticket_id: ticket_id, reason: "seq_gap" } }

      with_previous = Message.where(ticket_id: ticket_ids)
                             .select("ticket_id, created_at, lag(created_at) OVER (PARTITION BY ticket_id ORDER BY seq) AS previous_at")
      going_back = Message.unscoped.from(with_previous, :ordered).where("ordered.previous_at > ordered.created_at")
                          .distinct.pluck("ordered.ticket_id")
                          .map { |ticket_id| { ticket_id: ticket_id, reason: "time_goes_back" } }

      gaps + going_back
    end

    def orphans(ticket_ids)
      tickets = Ticket.where(id: ticket_ids)
      silent = tickets.where(mode: "ai").where(awaiting_agent_since: ...(@now - @orphan_after)).pluck(:id)
                      .map { |id| { ticket_id: id, reason: "agent_silence_not_escalated" } }
      queueless = tickets.where(mode: %w[pending_human human], queue_id: nil).pluck(:id)
                         .map { |id| { ticket_id: id, reason: "escalated_without_queue" } }
      silent + queueless
    end
  end
end
