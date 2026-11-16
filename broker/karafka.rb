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

  # O tópico principal e os dois estágios de retry usam o mesmo consumidor. A DLQ não tem consumidor
  # automático: é tratada pela rotina bin/dlq.
  routes.draw do
    Broker::ReplyPipeline.stages.each_key do |name|
      topic name do
        consumer Broker::RepliesConsumer
      end
    end
  end

  # O broker é o dono dos tópicos da borda do agente. `karafka topics migrate` os cria na subida.
  declaratives.draw do
    replies = Broker::Config.replies_topic
    [ Broker::Config.messages_topic, replies, "#{replies}.retry-1", "#{replies}.retry-2", "#{replies}.dlq" ].each do |name|
      topic name do
        partitions Broker::Config.partitions
        replication_factor 1
      end
    end
  end
end
