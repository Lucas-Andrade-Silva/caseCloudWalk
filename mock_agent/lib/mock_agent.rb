require "json"
require "logger"
require "karafka"

# Agente de IA simulado. O agente real da CloudWalk é externo e fica fora do escopo do projeto;
# este mock ocupa o lugar dele para a plataforma poder ser exercitada de ponta a ponta.
#
# Consome as mensagens que o broker publica no Kafka e produz as respostas em outro tópico.
# É determinístico: a mesma mensagem gera sempre a mesma resposta.
module MockAgent
  module Config
    module_function

    def kafka_bootstrap_servers = ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
    def messages_topic = ENV.fetch("MESSAGES_TOPIC", "helpdesk.messages")
    def replies_topic = ENV.fetch("REPLIES_TOPIC", "agent.replies")
  end

  def self.logger
    @logger ||= Logger.new($stdout, progname: "mock-agent").tap { $stdout.sync = true }
  end
end

require "mock_agent/responder"
require "mock_agent/messages_consumer"
