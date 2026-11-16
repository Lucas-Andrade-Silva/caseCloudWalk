# frozen_string_literal: true

# Base de todos os consumidores Karafka. Cada mensagem passa pelo Inbox, então a reentrega do
# Kafka não repete o efeito. A subclasse implementa só #handle.
class ApplicationConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      process_once(message)
      mark_as_consumed(message)
    end
  end

  # Efeito de negócio de uma mensagem. Roda dentro da transação do Inbox.
  def handle(message)
    raise NotImplementedError, "#{self.class.name} precisa implementar #handle"
  end

  private

  def process_once(message)
    Inbox.process(consumer: self.class.name, event_id: message.headers["event_id"]) do
      handle(message)
    end
  end
end
