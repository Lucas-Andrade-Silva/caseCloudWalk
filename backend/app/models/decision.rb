# Registro de auditoria de uma decisão de roteamento (ADR 0005, R5). Nunca muda depois de gravado.
class Decision < ApplicationRecord
  belongs_to :ticket
  belongs_to :brand
  belongs_to :rule_set, optional: true

  def readonly? = persisted?
end
