# Registro de que um consumidor já aplicou o efeito de um evento. Ver Inbox.
class ProcessedEvent < ApplicationRecord
  self.primary_key = %i[consumer_name event_id]
end
