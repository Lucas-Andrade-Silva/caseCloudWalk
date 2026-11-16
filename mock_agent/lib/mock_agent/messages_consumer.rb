module MockAgent
  # Consome as mensagens da plataforma e publica a resposta do agente.
  # A resposta só conta como dada depois de o Kafka confirmar; aí o offset é confirmado.
  class MessagesConsumer < Karafka::BaseConsumer
    def consume
      messages.each do |message|
        reply = responder.reply_for(parse(message.raw_payload), event_id: message.headers["event_id"])

        if reply
          Karafka.producer.produce_sync(
            topic: Config.replies_topic,
            key: reply["ticket_id"],
            payload: JSON.generate(reply)
          )
        else
          MockAgent.logger.info("mensagem ignorada (offset #{message.offset})")
        end

        mark_as_consumed(message)
      end
    end

    private

    def responder
      @responder ||= Responder.new
    end

    def parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end
end
