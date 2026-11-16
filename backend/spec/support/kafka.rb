# Apoio para os testes marcados com :kafka (Kafka real do Compose).

# Cria tópicos descartáveis, com nome único por execução, e os apaga no fim da suíte.
module KafkaTestTopics
  @created = []

  class << self
    def create(name = "test.#{SecureRandom.hex(6)}")
      Karafka::Admin.create_topic(name, 1, 1)
      @created << name
      name
    end

    def delete_all
      @created.each { |name| Karafka::Admin.delete_topic(name) }
      @created.clear
    end
  end
end

# Consumidor de teste: registra entregas e efeitos em memória.
class RoundTripTestConsumer < ApplicationConsumer
  @effects = Concurrent::Array.new
  @deliveries = Concurrent::AtomicFixnum.new(0)

  class << self
    def reset
      @effects.clear
      @deliveries.value = 0
    end

    def effects = @effects.to_a
    def deliveries = @deliveries.value
    def record_effect(payload) = @effects << payload
    def record_delivery = @deliveries.increment

    def wait_for_deliveries(count, timeout:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      sleep 0.1 while deliveries < count && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end
  end

  def consume
    messages.each do |message|
      process_once(message)
      self.class.record_delivery
    end
  end

  def handle(message)
    self.class.record_effect(message.payload)
  end
end

# Roda o servidor Karafka dentro do processo de teste, uma vez por suíte.
module KarafkaEmbedded
  ROUND_TRIP_TOPIC = "test.roundtrip.#{SecureRandom.hex(6)}".freeze

  class << self
    def start
      return if @started

      KafkaTestTopics.create(ROUND_TRIP_TOPIC)
      Karafka::App.routes.draw do
        topic ROUND_TRIP_TOPIC do
          consumer RoundTripTestConsumer
        end
      end
      Karafka::Embedded.start
      @started = true
    end

    def stop
      return unless @started

      Karafka::Embedded.stop
      @started = false
    end
  end
end

RSpec.configure do |config|
  config.after(:suite) do
    KarafkaEmbedded.stop
    KafkaTestTopics.delete_all
  end
end
