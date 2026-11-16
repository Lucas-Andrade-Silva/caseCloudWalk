# Consumo idempotente. O Kafka entrega at-least-once; o Inbox garante que o efeito de cada evento
# acontece uma vez por consumidor.
#
# O registro em processed_events e o efeito ficam na mesma transação: ou os dois valem, ou nenhum.
module Inbox
  class MissingEventId < StandardError; end

  # Executa o bloco se este consumidor ainda não processou o evento.
  # Devolve true se executou e false se era duplicata.
  def self.process(consumer:, event_id:)
    raise MissingEventId, "evento sem event_id para o consumidor #{consumer}" if event_id.blank?

    ProcessedEvent.transaction(requires_new: true) do
      # ON CONFLICT DO NOTHING: uma entrega concorrente do mesmo evento espera esta transação
      # terminar e, se ela confirmar, não insere nada.
      inserted = ProcessedEvent.insert(
        { consumer_name: consumer, event_id: event_id },
        unique_by: %i[consumer_name event_id],
        returning: %i[event_id]
      )
      next false if inserted.rows.empty?

      yield
      true
    end
  end
end
