# Nível de prioridade e o prazo da primeira resposta humana depois da escalação (ADR 0004, H3).
class PriorityLevel < ApplicationRecord
  self.primary_key = "code"

  DEFAULTS = [
    { code: "p1", name: "urgente", first_response_minutes: 5, position: 1 },
    { code: "p2", name: "alta", first_response_minutes: 15, position: 2 },
    { code: "p3", name: "normal", first_response_minutes: 60, position: 3 },
    { code: "p4", name: "baixa", first_response_minutes: 240, position: 4 }
  ].freeze

  # Cria os níveis que faltam, sem mexer nos que a operação já editou.
  def self.ensure_defaults!
    insert_all(DEFAULTS, unique_by: :code)
  end

  def first_response_deadline(from) = from + first_response_minutes.minutes
end
