# frozen_string_literal: true

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "broker"

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = { "bootstrap.servers": Broker::Config.kafka_bootstrap_servers }
    config.client_id = "helpdesk-broker"
    config.group_id = "helpdesk_broker_#{Karafka.env}"
    # O padrão do Karafka espera até 1 s para juntar um lote. Em atendimento, a latência de uma
    # mensagem isolada importa mais; com fila cheia o lote enche antes desse prazo de qualquer forma.
    config.max_wait_time = Integer(ENV.fetch("KAFKA_MAX_WAIT_MS", "100"))
  end

  unless Karafka.env.test?
    Karafka.monitor.subscribe(Karafka::Instrumentation::LoggerListener.new(log_polling: false))
  end

  routes.draw do
    topic Broker::Config.replies_topic do
      consumer Broker::RepliesConsumer
    end
  end

  # O broker é o dono dos tópicos da borda do agente. `karafka topics migrate` os cria na subida.
  declaratives.draw do
    [ Broker::Config.messages_topic, Broker::Config.replies_topic ].each do |name|
      topic name do
        partitions Broker::Config.partitions
        replication_factor 1
      end
    end
  end
end
