# Modo Incidente (ADR 0009, W1 e W2). Um ticket entra num grupo pela categoria que a LLM deu; sem categoria
# útil, pela primeira tag. "outro" e "falar_com_humano" não servem: muitos pedidos assim não indicam uma falha
# comum. Limite e janela ajustáveis por ambiente (INCIDENT_THRESHOLD, INCIDENT_WINDOW_MINUTES).
module Incidents
  NOT_A_SIGNAL = %w[outro falar_com_humano].freeze

  # A mesma regra de key_for, em SQL, para contar os tickets parecidos no banco.
  KEY_SQL = <<~SQL.squish.freeze
    CASE
      WHEN tickets.llm_facts->>'category' IS NOT NULL
        AND tickets.llm_facts->>'category' NOT IN ('outro', 'falar_com_humano')
        THEN 'categoria:' || (tickets.llm_facts->>'category')
      WHEN cardinality(tickets.tags) > 0 THEN 'tag:' || tickets.tags[1]
    END
  SQL

  module_function

  def threshold = Integer(ENV.fetch("INCIDENT_THRESHOLD", "5"))
  def window = Integer(ENV.fetch("INCIDENT_WINDOW_MINUTES", "10")).minutes

  # [chave, rótulo] do grupo do ticket, ou nil quando ele não tem sinal que agrupe.
  def key_for(ticket)
    category = ticket.llm_facts.to_h["category"]
    if category.present? && NOT_A_SIGNAL.exclude?(category)
      [ "categoria:#{category}", category ]
    elsif (tag = ticket.tags.first)
      [ "tag:#{tag}", tag ]
    end
  end
end
