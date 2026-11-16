# Fila de atendimento humano. Chama-se TicketQueue porque Queue já é uma classe do Ruby.
# Pertence a uma marca e é atendida por uma equipe.
class TicketQueue < ApplicationRecord
  self.table_name = "queues"

  belongs_to :brand
  belongs_to :team
  has_many :tickets, foreign_key: :queue_id

  validates :slug, format: { with: /\A[a-z0-9-]{1,64}\z/ }, uniqueness: true
  validates :name, presence: true

  def self.default_for(brand) = find_by(brand: brand, default: true)
end
