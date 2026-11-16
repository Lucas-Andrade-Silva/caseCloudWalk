# Fila de atendimento humano. Chama-se TicketQueue porque Queue já é uma classe do Ruby.
class TicketQueue < ApplicationRecord
  self.table_name = "queues"

  belongs_to :brand
  has_many :queue_memberships, foreign_key: :queue_id
  has_many :tickets, foreign_key: :queue_id

  def self.default_for(brand) = find_by(brand: brand, default: true)
end
