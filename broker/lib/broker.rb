require "json"
require "logger"
require "karafka"
require "rack"

# Broker de mensageria entre a plataforma de help desk e o agente de IA (ADR 0003, E1).
#
#   plataforma --webhook assinado--> broker --Kafka--> agente
#   agente --Kafka--> broker --API da plataforma (usuário bot)--> plataforma
#
# Não tem banco nem estado. A entrega é at-least-once nas duas direções; quem recebe é idempotente.
module Broker
  # Configuração lida do ambiente (ver compose.yaml).
  module Config
    module_function

    def kafka_bootstrap_servers = ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
    def messages_topic = ENV.fetch("MESSAGES_TOPIC", "helpdesk.messages")
    def replies_topic = ENV.fetch("REPLIES_TOPIC", "agent.replies")
    def partitions = Integer(ENV.fetch("KAFKA_PARTITIONS", "12"))
    def webhook_secrets = ENV.fetch("BROKER_WEBHOOK_SECRETS", "").split(",").map(&:strip).reject(&:empty?)
    def platform_url = ENV.fetch("PLATFORM_URL")
    def bot_api_token = ENV.fetch("BOT_API_TOKEN")
  end

  def self.logger
    @logger ||= Logger.new($stdout, progname: "broker").tap { $stdout.sync = true }
  end
end

require "broker/signature"
require "broker/webhook_app"
require "broker/platform_client"
require "broker/reply_forwarder"
require "broker/reply_pipeline"
require "broker/dlq"
require "broker/replies_consumer"
