require "net/http"

module Broker
  # Decide o que fazer com uma resposta do agente lida do Kafka (spec 05). Não fala com o Kafka direto:
  # devolve uma ação para o consumidor executar, e o que precisa publicar vai pelo produtor injetado.
  #
  #   agent.replies --falha--> retry-1 (10 s) --falha--> retry-2 (60 s) --falha--> dlq
  #
  # Plataforma fora do ar não gasta tentativa: pausa e repete a mesma mensagem, para uma queda da
  # plataforma não mandar tudo para a DLQ.
  class ReplyPipeline
    Envelope = Data.define(:topic, :key, :raw_payload, :headers, :timestamp)

    Action = Data.define(:kind, :seconds) do
      def self.ack = new(kind: :ack, seconds: 0)
      def self.pause(seconds) = new(kind: :pause, seconds: seconds)
      def pause? = kind == :pause
    end

    Stage = Data.define(:delay, :next_topic)

    UNAVAILABLE_PAUSE = 5
    NETWORK_ERRORS = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout,
      SocketError, EOFError
    ].freeze

    def self.stages(base = Config.replies_topic)
      {
        base => Stage.new(delay: 0, next_topic: "#{base}.retry-1"),
        "#{base}.retry-1" => Stage.new(delay: 10, next_topic: "#{base}.retry-2"),
        "#{base}.retry-2" => Stage.new(delay: 60, next_topic: "#{base}.dlq")
      }
    end

    def initialize(forwarder: ReplyForwarder.new, producer: Karafka.producer, logger: Broker.logger,
                   stages: self.class.stages)
      @forwarder = forwarder
      @producer = producer
      @logger = logger
      @stages = stages
    end

    # Cada resposta é tratada dentro do trace que veio nos headers do Kafka (ADR 0008, O2).
    def handle(message, now: Time.now)
      OpenTelemetry::Context.with_current(Tracing.from_headers(message.headers)) do
        Tracing.tracer.in_span("kafka consume #{message.topic}", kind: :consumer,
                                                                 attributes: { "messaging.system" => "kafka",
                                                                               "messaging.destination.name" => message.topic }) do
          decide(message, now)
        end
      end
    end

    private

    def decide(message, now)
      stage = @stages.fetch(message.topic)
      wait = (message.timestamp + stage.delay - now).ceil
      return Action.pause(wait) if wait.positive?

      @forwarder.forward(message.raw_payload)
      Action.ack
    rescue ReplyForwarder::PlatformUnavailable, *NETWORK_ERRORS => error
      @logger.warn("plataforma indisponível (#{error.class}: #{error.message}); repetindo em #{UNAVAILABLE_PAUSE} s")
      Action.pause(UNAVAILABLE_PAUSE)
    rescue StandardError => error
      move_on(message, stage, error)
      Action.ack
    end


    def move_on(message, stage, error)
      attempt = message.headers.fetch("x-attempt", "0").to_i + 1
      @producer.produce_sync(
        topic: stage.next_topic,
        key: message.key,
        payload: message.raw_payload,
        headers: message.headers.merge(
          "x-attempt" => attempt.to_s,
          "x-error" => "#{error.class}: #{error.message}"[0, 500],
          "x-original-topic" => message.headers.fetch("x-original-topic", message.topic)
        )
      )
      @logger.warn("resposta enviada para #{stage.next_topic} (tentativa #{attempt}): #{error.message}")
    end
  end
end
