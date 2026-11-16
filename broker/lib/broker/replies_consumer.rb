module Broker
  # Consome as respostas do agente e as entrega à plataforma, uma a uma e em ordem.
  # O offset só é confirmado depois que a plataforma respondeu; se a entrega falha, o Karafka pausa
  # a partição e tenta de novo.
  class RepliesConsumer < Karafka::BaseConsumer
    def consume
      messages.each do |message|
        forwarder.forward(message.raw_payload)
        mark_as_consumed(message)
      end
    end

    private

    def forwarder
      @forwarder ||= ReplyForwarder.new
    end
  end
end
