# Resumo de encerramento de um ticket (ADR 0006, M3). Cita o ticket de origem e expira no fim da janela da
# memória. Pode ser regenerado do histórico: o gerador atual é um template; a LLM troca só o gerador.
class ClosingSummary < ApplicationRecord
  belongs_to :ticket
  belongs_to :brand
  belongs_to :customer

  scope :current, ->(now = Time.current) { where("expires_at > ?", now) }
end
