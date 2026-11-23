module Tickets
  # "Por que a IA decidiu" (ADR 0009, W1): a cadeia de decisão de um ticket, montada da auditoria que a
  # plataforma já grava. Fatos da LLM com confiança, modelo e versão do prompt; regra que casou, com a versão
  # das regras; escalação; brief; fallbacks e o motivo deles; o texto do cliente como a LLM o viu (redigido);
  # e o trace ponta a ponta. Nunca devolve o texto original nem o hash dele.
  module Explain
    # Evento da linha do tempo -> passo da cadeia, e a decisão de regras que ele provoca (se houver).
    EVENT_STEPS = {
      "ticket.opened" => [ "opened", "routing.opening" ],
      "ticket.enriched" => [ "llm_facts", "routing.enrichment" ],
      "enrichment.skipped" => [ "llm_fallback", nil ],
      "ticket.escalated" => [ "escalated", "routing.escalation" ],
      "brief.summarized" => [ "brief", nil ],
      "brief.summary_skipped" => [ "brief_fallback", nil ],
      "ticket.incident_linked" => [ "incident", nil ]
    }.freeze
    # A decisão é gravada na mesma transação do evento, com o relógio do banco: casa por proximidade.
    PAIRING_WINDOW = 5.seconds
    HIDDEN_FACTS = %w[message_text message_text_sha256 stage].freeze

    module_function

    def call(ticket)
      first_text = ticket.messages.where(sender: "customer").order(:seq).first&.body
      redaction = Llm::Redactor.call(first_text.to_s)
      { ticket_id: ticket.id, redacted_text: redaction.text, redactions: redaction.findings,
        trace_id: trace_id(ticket), steps: steps(ticket) }
    end

    def steps(ticket)
      decisions = Decision.where(ticket_id: ticket.id).includes(:rule_set).order(:id).to_a
      result = []
      ticket.conversation_events.order(:id).each do |event|
        kind, decision_step = EVENT_STEPS[event.kind]
        next unless kind

        result << event_step(kind, event)
        decision = take_decision(decisions, decision_step, event.created_at) if decision_step
        result << rule_step(decision) if decision
      end
      result + decisions.map { |decision| rule_step(decision) }
    end

    def take_decision(decisions, step, at)
      index = decisions.index { |decision| decision.step == step && (decision.created_at - at).abs <= PAIRING_WINDOW }
      index && decisions.delete_at(index)
    end

    def event_step(kind, event)
      data = event.data.to_h
      base = { kind: kind, at: event.created_at.iso8601(3), actor: event.actor }
      case kind
      when "opened" then base.merge(channel: data["channel"])
      when "llm_facts"
        base.merge(data.slice("category", "language", "frustration", "confidence", "source", "model", "prompt_version"))
            .merge(accepted: data["category"].present?, min_confidence: Llm::Enrich.min_confidence)
      when "llm_fallback", "brief_fallback" then base.merge(reason: data["reason"])
      when "escalated" then base.merge(trigger: data["trigger"], reason: data["reason"], priority: data["priority"])
      when "brief" then base.merge(data.slice("source", "model", "prompt_version"))
      when "incident" then base.merge(incident_id: data["incident_id"], key: data["key"])
      end
    end

    def rule_step(decision)
      rule = decision.rule_set&.rules&.find { |candidate| candidate["id"] == decision.matched_rule_id }
      {
        kind: "rule", at: decision.created_at.iso8601(3), actor: decision.actor, step: decision.step,
        rule_set_version: decision.rule_set_version,
        rule: rule && rule.slice("id", "name", "when"),
        output: decision.output,
        facts: decision.facts.except(*HIDDEN_FACTS).compact
      }
    end

    def trace_id(ticket)
      # O primeiro evento do ticket que levou trace: sem trace ativo, o outbox não grava traceparent.
      traceparent = OutboxEvent.where(key: ticket.id).where("headers ? 'traceparent'").order(:id).pick(:headers)&.dig("traceparent")
      traceparent&.split("-")&.second
    end
  end
end
