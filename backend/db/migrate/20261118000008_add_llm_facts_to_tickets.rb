# Fatos do LLM no ticket (ADR 0008, L1 a L3): categoria, idioma, frustração e confiança, com origem, modelo e
# versão do prompt. Vazio quando o ticket não foi enriquecido.
class AddLlmFactsToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :llm_facts, :jsonb, null: false, default: {}
  end
end
