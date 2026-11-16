# Evento a publicar no Kafka. É gravado na mesma transação do efeito de negócio que o originou,
# e o relay (Outbox::Relay) o publica depois. Assim não existe escrita dupla.
class OutboxEvent < ApplicationRecord
  # UUID v7 é ordenável por tempo. É a identidade do evento para o dedupe no consumo.
  attribute :event_id, default: -> { SecureRandom.uuid_v7 }

  scope :pending, -> { where(published_at: nil).order(:id) }
end
