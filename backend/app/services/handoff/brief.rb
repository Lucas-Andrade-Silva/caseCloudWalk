module Handoff
  # Brief do handoff: o que o analista precisa saber para assumir sem reler a conversa inteira.
  #
  # Nesta versão é um template preenchido pela plataforma (fonte "template"). O resumo por LLM entra
  # depois, mantendo este template como fallback (ADR 0002, D5 e D9).
  module Brief
    RECENT_MESSAGES = 6
    VERSION = 1

    TRIGGER_LABELS = {
      "agent_requested" => "Escalado pelo agente",
      "agent_timeout" => "Escalado pela plataforma porque o agente não respondeu",
      "analyst_takeover" => "Assumido pelo analista"
    }.freeze

    module_function

    def build(ticket:, trigger:, reason:, now:)
      messages = ticket.messages.order(:seq).to_a
      last_customer = messages.reverse.find { |message| message.sender == "customer" }
      ai_seconds = (now - ticket.created_at).round

      {
        version: VERSION,
        source: "template",
        trigger: trigger,
        reason: reason,
        brand: ticket.brand.slug,
        channel: ticket.channel,
        customer: { external_id: ticket.customer.external_id, name: ticket.customer.name },
        ai_duration_seconds: ai_seconds,
        message_count: messages.size,
        last_customer_message: last_customer&.body,
        recent_messages: messages.last(RECENT_MESSAGES).map do |message|
          { seq: message.seq, sender: message.sender, text: message.body, stale: message.stale }
        end,
        summary: summary(ticket, trigger, reason, messages.size, ai_seconds, last_customer)
      }
    end

    def summary(ticket, trigger, reason, count, ai_seconds, last_customer)
      customer = ticket.customer
      who = [ customer.name, "(#{customer.external_id})" ].compact.join(" ")
      text = "#{TRIGGER_LABELS.fetch(trigger, trigger)} (motivo: #{reason}). " \
             "Cliente #{who}, #{ticket.brand.name} via #{ticket.channel}, " \
             "#{count} mensagens em #{duration(ai_seconds)} com a IA."
      last_customer ? "#{text} Último pedido do cliente: \"#{last_customer.body}\"" : text
    end

    def duration(seconds)
      return "#{seconds} s" if seconds < 60
      return "#{seconds / 60} min" if seconds < 3600

      "#{seconds / 3600} h #{(seconds % 3600) / 60} min"
    end
  end
end
