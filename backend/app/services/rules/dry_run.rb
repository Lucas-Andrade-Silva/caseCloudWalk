module Rules
  # Mostra o que mudaria se um rascunho fosse publicado: aplica a versão publicada e o rascunho aos
  # últimos tickets da marca e compara. Só lê; não grava nada.
  module DryRun
    MAX_LIMIT = 1000

    module_function

    def call(candidate:, limit: 200)
      brand = candidate.brand
      current = RuleSet.published_for(brand)
      tickets = Ticket.where(brand: brand).order(created_at: :desc, id: :desc).limit(limit.clamp(1, MAX_LIMIT))

      changes = []
      evaluated = 0
      tickets.includes(:brand).each do |ticket|
        facts = Facts.for_opening(ticket)
        before = summary(Router.evaluate(brand: brand, facts: facts, rule_set: current))
        after = summary(Router.evaluate(brand: brand, facts: facts, rule_set: candidate))
        evaluated += 1
        changes << { ticket_id: ticket.id, before: before, after: after } if before != after
      end

      { current_version: current&.version, candidate_version: candidate.version,
        evaluated: evaluated, changed: changes.size, changes: changes }
    end

    def summary(outcome)
      { rule_id: outcome.rule&.fetch("id"), queue: outcome.queue&.slug, priority: outcome.priority, tags: outcome.tags }
    end
  end
end
