module Llm
  # Enriquecimento do ticket (ADR 0008, L1 a L3): o LLM dá categoria, idioma e frustração; as regras decidem.
  # Roda num job, depois da entrada. Sem LLM, o ticket segue com o roteamento por regras que já tem.
  module Enrich
    # Abaixo disso, a categoria não vira fato (ADR 0002, D4: confiança mínima). LLM_MIN_CONFIDENCE ajusta.
    def self.min_confidence = Float(ENV.fetch("LLM_MIN_CONFIDENCE", "0.5"))

    def self.call(ticket, client: Llm.client)
      text = ticket.messages.where(sender: "customer").order(:seq).first&.body
      result = client.call(task: "enrich", input: text.to_s)

      ticket.with_lock do
        next ticket.record_event!(kind: "enrichment.skipped", actor: "llm", data: { reason: result.error }) unless result.ok

        facts = result.data.dup
        facts["category"] = nil if facts["confidence"].to_f < min_confidence
        meta = { "source" => result.source, "model" => result.model, "prompt_version" => result.prompt_version,
                 "enriched_at" => Time.current.iso8601(3) }
        ticket.update!(llm_facts: facts.merge(meta))
        # A auditoria guarda os fatos, nunca o texto do cliente.
        ticket.record_event!(kind: "ticket.enriched", actor: "llm", data: facts.merge(meta.except("enriched_at")))
        Rules::Router.route_enrichment!(ticket) if ticket.ai?
        # A categoria pode mudar o grupo do ticket no Modo Incidente (ADR 0009, W2).
        ActiveRecord.after_all_transactions_commit { DetectIncidentJob.perform_async(ticket.id) }
      end
    end
  end
end
