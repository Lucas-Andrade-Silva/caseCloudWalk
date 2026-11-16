# frozen_string_literal: true

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "mock_agent"

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = { "bootstrap.servers": MockAgent::Config.kafka_bootstrap_servers }
    config.client_id = "mock-agent"
    config.group_id = "mock_agent_#{Karafka.env}"
    # O padrão do Karafka espera até 1 s para juntar um lote. Em atendimento, a latência de uma
    # mensagem isolada importa mais; com fila cheia o lote enche antes desse prazo de qualquer forma.
    config.max_wait_time = Integer(ENV.fetch("KAFKA_MAX_WAIT_MS", "100"))
  end

  unless Karafka.env.test?
    Karafka.monitor.subscribe(Karafka::Instrumentation::LoggerListener.new(log_polling: false))
  end

  # Os tópicos pertencem ao broker, que os cria na subida.
  routes.draw do
    topic MockAgent::Config.messages_topic do
      consumer MockAgent::MessagesConsumer
    end
  end
end
