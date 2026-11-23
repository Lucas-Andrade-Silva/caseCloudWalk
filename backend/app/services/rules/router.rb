module Rules
  # Aplica as regras publicadas da marca a um ticket e registra a decisão (ADR 0005, R2 e R5).
  module Router
    Outcome = Data.define(:rule_set, :rule, :queue, :priority, :tags) do
      def to_output = { "queue" => queue&.slug, "priority" => priority, "tags" => tags }
    end

    module_function

    def evaluate(brand:, facts:, rule_set: RuleSet.published_for(brand))
      rule = rule_set && Evaluator.first_match(rule_set.rules, facts)
      action = rule ? rule["then"] : {}
      queue = action["queue"] && TicketQueue.find_by(slug: action["queue"], brand_id: brand.id)
      Outcome.new(rule_set: rule_set, rule: rule, queue: queue, priority: action["priority"], tags: action["tags"] || [])
    end

    # Na abertura: prioridade, tags e fila prevista. O ticket continua com a IA.
    def route_opening!(ticket)
      facts = Facts.for_opening(ticket)
      outcome = evaluate(brand: ticket.brand, facts: facts)
      ticket.update!(priority: outcome.priority || ticket.priority, tags: outcome.tags, queue: outcome.queue)
      record!(ticket: ticket, step: "routing.opening", facts: facts, outcome: outcome)
      outcome
    end

    # Depois do enriquecimento (ADR 0008, L1): reavalia com os fatos do LLM enquanto o ticket está com a IA.
    def route_enrichment!(ticket)
      facts = Facts.for_opening(ticket)
      outcome = evaluate(brand: ticket.brand, facts: facts)
      ticket.update!(priority: outcome.priority || ticket.priority, tags: outcome.tags, queue: outcome.queue)
      record!(ticket: ticket, step: "routing.enrichment", facts: facts, outcome: outcome)
      outcome
    end

    def record!(ticket:, step:, facts:, outcome:)
      Decision.create!(
        ticket: ticket,
        brand_id: ticket.brand_id,
        step: step,
        actor: "rule",
        rule_set: outcome.rule_set,
        rule_set_version: outcome.rule_set&.version,
        matched_rule_id: outcome.rule&.fetch("id"),
        facts: without_text(facts),
        output: outcome.to_output
      )
    end

    # A auditoria não copia o texto do cliente: guarda só o hash (ADR 0005, R5).
    def without_text(facts)
      text = facts["message_text"]
      facts.except("message_text").merge("message_text_sha256" => text && Digest::SHA256.hexdigest(text))
    end
  end
end
