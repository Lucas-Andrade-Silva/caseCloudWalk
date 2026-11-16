# Evento a publicar no broker. É gravado na mesma transação do efeito de negócio que o originou,
# e o relay (Outbox::Relay) o entrega depois. Assim não existe escrita dupla.
#
# Um evento recusado de vez fica estacionado (`dead_at`) e retém os próximos eventos da mesma chave
# (o mesmo ticket), para a ordem do ticket não se perder (playbook §3.5).
class OutboxEvent < ApplicationRecord
  # UUID v7 é ordenável por tempo. É a identidade do evento para o dedupe no consumo.
  attribute :event_id, default: -> { SecureRandom.uuid_v7 }

  scope :dead, -> { where(published_at: nil, discarded_at: nil).where.not(dead_at: nil).order(:id) }
  scope :pending, lambda {
    where(published_at: nil, dead_at: nil, discarded_at: nil)
      .where.not(key: unscoped.dead.select(:key))
      .order(:id)
  }

  # Volta o estacionado para a fila. Ele sai antes dos que ficaram retidos, porque o id é menor.
  # Grava sempre: o objeto em memória pode ser anterior ao estacionamento e achar que não há o que mudar.
  def retry!
    update_columns(dead_at: nil)
  end

  # Desiste do estacionado e libera os eventos retidos do mesmo ticket.
  def discard!
    update!(discarded_at: Time.current)
  end
end
