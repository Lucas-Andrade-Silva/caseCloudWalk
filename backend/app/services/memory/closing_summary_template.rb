module Memory
  # Resumo de encerramento por template (ADR 0006, M3): factual, a partir do histórico do ticket. Função pura,
  # então pode ser regenerado. A LLM entra depois como outro gerador, com este como fallback.
  module ClosingSummaryTemplate
    VERSION = 1
    SOURCE = "template"

    RESOLUTION_LABELS = {
      "resolved" => "resolvido",
      "no_customer_response" => "cliente não respondeu",
      "duplicate" => "duplicado",
      "forwarded" => "encaminhado"
    }.freeze

    module_function

    def build(ticket)
      first_request = ticket.messages.where(sender: "customer").order(:seq).first
      parts = [
        "Ticket #{ticket.id} via #{ticket.channel}, aberto em #{format_time(ticket.created_at)} " \
        "e fechado em #{format_time(ticket.closed_at)}.",
        human_part(ticket),
        (first_request && "Pedido inicial: \"#{first_request.body}\"."),
        "Resolução: #{RESOLUTION_LABELS.fetch(ticket.resolution_code, ticket.resolution_code)}.",
        (ticket.resolution_note.present? && "Nota: \"#{ticket.resolution_note}\"")
      ]
      parts.compact_blank.join(" ")
    end

    def human_part(ticket)
      return "Atendido só pela IA." if ticket.escalation_trigger.nil?

      trigger = Handoff::Brief::TRIGGER_LABELS.fetch(ticket.escalation_trigger, ticket.escalation_trigger)
      "Passou para humano: #{trigger} (motivo: #{ticket.escalation_reason}), " \
        "fila #{ticket.queue&.slug || 'sem fila'}, prioridade #{ticket.priority}."
    end

    def format_time(time) = time.utc.strftime("%d/%m/%Y %H:%M UTC")
  end
end
