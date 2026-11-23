module Outbox
  # Entrega ao broker os eventos pendentes do outbox, em ordem de id.
  #
  # A entrega é at-least-once: se o processo cair depois de publicar e antes de marcar, o evento
  # sai de novo, e o consumidor descarta a duplicata pelo event_id (ver Inbox).
  #
  # - Recusa definitiva do broker: o evento fica estacionado, os próximos do mesmo ticket ficam retidos e
  #   o lote segue com os outros tickets.
  # - Falha temporária: conta a tentativa, guarda o erro e para o lote; o RelayProcess tenta de novo.
  class Relay
    DEFAULT_BATCH_SIZE = 100

    def initialize(producer: WebhookPublisher.new, batch_size: DEFAULT_BATCH_SIZE)
      @producer = producer
      @batch_size = batch_size
    end

    # Publica um lote e devolve quantos eventos saíram. Se a publicação falhar no meio, o erro
    # sobe, mas o que já saiu fica marcado, para não ser reenviado sem necessidade.
    def publish_pending
      published_ids = []
      parked_keys = Set.new

      OutboxEvent.pending.limit(@batch_size).each do |event|
        next if parked_keys.include?(event.key)

        begin
          deliver(event)
          published_ids << event.id
        rescue WebhookPublisher::Rejected => error
          park(event, error)
          parked_keys << event.key
        rescue StandardError => error
          record_failure(event, error)
          raise
        end
      end

      published_ids.size
    ensure
      mark_published(published_ids)
    end

    private

    # Entrega dentro de um span filho do trace que criou o evento; o webhook leva o contexto desse span,
    # e o broker o passa adiante pelo Kafka (ADR 0008, O2).
    def deliver(event)
      parent = OpenTelemetry.propagation.extract(event.headers)
      OpenTelemetry::Context.with_current(parent) do
        TRACER.in_span("outbox deliver", kind: :producer,
                                          attributes: { "messaging.destination.name" => event.topic,
                                                        "messaging.message.id" => event.event_id }) do
          message = message_for(event)
          carrier = {}
          OpenTelemetry.propagation.inject(carrier)
          message[:headers] = message[:headers].merge(carrier)
          @producer.produce_sync(message)
        end
      end
    end

    TRACER = OpenTelemetry.tracer_provider.tracer("helpdesk.outbox")

    def message_for(event)
      {
        topic: event.topic,
        key: event.key,
        payload: event.payload.to_json,
        headers: event.headers.transform_values(&:to_s).merge("event_id" => event.event_id)
      }
    end

    def park(event, error)
      event.update_columns(dead_at: Time.current, attempts: event.attempts + 1, last_error: describe(error))
    end

    def record_failure(event, error)
      event.update_columns(attempts: event.attempts + 1, last_error: describe(error))
    end

    def describe(error) = "#{error.class}: #{error.message}".truncate(1000)

    def mark_published(ids)
      return if ids.empty?

      OutboxEvent.where(id: ids).update_all(published_at: Time.current)
    end
  end
end
