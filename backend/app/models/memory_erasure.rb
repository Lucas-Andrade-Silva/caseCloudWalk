# Registro de auditoria de uma exclusão de memória (ADR 0006, M4). Nunca muda depois de gravado.
class MemoryErasure < ApplicationRecord
  belongs_to :brand
  belongs_to :customer
  belongs_to :requested_by, class_name: "User"

  def readonly? = persisted?
end
