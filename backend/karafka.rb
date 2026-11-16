# frozen_string_literal: true

# Configuração do Karafka (consumidores) e do WaterDrop (produtor usado pelo relay do outbox).
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = { "bootstrap.servers": ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092") }
    config.client_id = "helpdesk"
    # O sufixo de ambiente impede que testes e desenvolvimento compartilhem offsets.
    config.group_id = "helpdesk_#{Rails.env}"
    # Em desenvolvimento, recria os consumidores a cada lote para o reload de código funcionar.
    config.consumer_persistence = !Rails.env.development?
  end

  unless Rails.env.test?
    Karafka.monitor.subscribe(Karafka::Instrumentation::LoggerListener.new(log_polling: false))
    Karafka.producer.monitor.subscribe(
      WaterDrop::Instrumentation::LoggerListener.new(Karafka.logger, log_messages: false)
    )
  end

  # Os consumidores de produto entram aqui nas próximas fatias (ex.: agent.replies).
  routes.draw do
  end
end
