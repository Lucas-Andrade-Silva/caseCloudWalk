# frozen_string_literal: true

require_relative "karafka"

run Broker.rack_app(
  Broker::WebhookApp.new(
    producer: Karafka.producer,
    secrets: Broker::Config.webhook_secrets,
    allowed_topics: [ Broker::Config.messages_topic ]
  )
)
