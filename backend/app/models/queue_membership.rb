# Quais filas um analista atende. Um analista pode atender filas de mais de uma marca.
class QueueMembership < ApplicationRecord
  self.primary_key = %i[user_id queue_id]

  belongs_to :user
  belongs_to :queue, class_name: "TicketQueue"
end
