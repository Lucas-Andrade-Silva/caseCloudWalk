# Pico de tickets parecidos da mesma marca (ADR 0009, W1 e W2). Agrupa os tickets para o analista responder e
# fechar todos de uma vez. Título e rascunho nascem de um template; a LLM os reescreve depois, se estiver ligada.
class Incident < ApplicationRecord
  STATUSES = %w[open resolved].freeze

  belongs_to :brand
  belongs_to :resolved_by, class_name: "User", optional: true
  has_many :tickets

  scope :open, -> { where(status: "open") }

  def open? = status == "open"
end
