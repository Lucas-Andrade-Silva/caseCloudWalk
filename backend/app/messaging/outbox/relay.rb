module Outbox
  # Publica no Kafka os eventos pendentes do outbox, em ordem de id.
  #
  # A entrega é at-least-once: se o processo cair depois de publicar e antes de marcar, o evento
  # sai de novo, e o consumidor descarta a duplicata pelo event_id (ver Inbox).
  class Relay
    DEFAULT_BATCH_SIZE = 100

    def initialize(producer: Karafka.producer, batch_size: DEFAULT_BATCH_SIZE)
      @producer = producer
      @batch_size = batch_size
    end

    # Publica um lote e devolve quantos eventos saíram. Se a publicação falhar no meio, o erro
    # sobe, mas o que já saiu fica marcado, para não ser reenviado sem necessidade.
    def publish_pending
      published_ids = []

      OutboxEvent.pending.limit(@batch_size).each do |event|
        @producer.produce_sync(message_for(event))
        published_ids << event.id
      end

      published_ids.size
    ensure
      mark_published(published_ids)
    end

    private

    def message_for(event)
      {
        topic: event.topic,
        key: event.key,
        payload: event.payload.to_json,
        headers: event.headers.transform_values(&:to_s).merge("event_id" => event.event_id)
      }
    end

    def mark_published(ids)
      return if ids.empty?

      OutboxEvent.where(id: ids).update_all(published_at: Time.current)
    end
  end
end
