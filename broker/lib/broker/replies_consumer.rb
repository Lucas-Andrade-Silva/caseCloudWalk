module Broker
  # Consome as respostas do agente (tópico principal e estágios de retry) e as entrega à plataforma,
  # uma a uma e em ordem por partição. A decisão de cada mensagem fica no ReplyPipeline.
  class RepliesConsumer < Karafka::BaseConsumer
    def consume
      messages.each do |message|
        action = pipeline.handle(envelope(message))

        if action.pause?
          # Volta a esta mesma mensagem depois da pausa; as seguintes da partição esperam.
          pause(message.offset, action.seconds * 1000)
          return
        end

        mark_as_consumed(message)
      end
    end

    private

    def pipeline
      @pipeline ||= ReplyPipeline.new
    end

    def envelope(message)
      ReplyPipeline::Envelope.new(topic: message.topic, key: message.key, raw_payload: message.raw_payload,
                                  headers: message.headers.to_h, timestamp: message.timestamp)
    end
  end
end
