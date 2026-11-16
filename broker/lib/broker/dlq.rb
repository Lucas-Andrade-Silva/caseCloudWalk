module Broker
  # Rotina da DLQ das respostas do agente (spec 05): listar, republicar e purgar.
  #
  # O Kafka não apaga mensagens. "Tratado" é o offset confirmado por um grupo de consumo só desta
  # rotina: listar mostra o que vem depois dele; republicar e purgar avançam o offset até o fim.
  class Dlq
    CONTROL_HEADERS = %w[x-attempt x-error x-original-topic].freeze

    def initialize(topic: "#{Config.replies_topic}.dlq", group: "helpdesk_broker_dlq_admin", logger: Broker.logger)
      @topic = topic
      @group = group
      @logger = logger
    end

    def list
      untreated.map do |message|
        { partition: message.partition, offset: message.offset, key: message.key,
          error: message.headers["x-error"], attempt: message.headers["x-attempt"],
          original_topic: message.headers["x-original-topic"], payload: message.raw_payload }
      end
    end

    # Republica no tópico de origem, sem os headers de controle (a contagem de tentativas recomeça).
    def replay
      messages = untreated
      messages.each do |message|
        Karafka.producer.produce_sync(
          topic: message.headers.fetch("x-original-topic"),
          key: message.key,
          payload: message.raw_payload,
          headers: message.headers.to_h.except(*CONTROL_HEADERS)
        )
      end
      mark_all_treated
      @logger.info("DLQ: #{messages.size} mensagem(ns) republicada(s)")
      messages.size
    end

    def purge
      count = untreated.size
      mark_all_treated
      @logger.info("DLQ: #{count} mensagem(ns) purgada(s)")
      count
    end

    private

    def partitions
      Karafka::Admin.topic_info(@topic).fetch(:partitions).map { |partition| partition.fetch(:partition_id) }
    end

    def untreated
      committed = Karafka::Admin.read_lags_with_offsets({ @group => [ @topic ] }, active_topics_only: false)
                                .dig(@group, @topic) || {}

      partitions.flat_map do |partition|
        low, high = Karafka::Admin.read_watermark_offsets(@topic, partition)
        start = [ committed.dig(partition, :offset).to_i, low ].max
        next [] if start >= high

        Karafka::Admin.read_topic(@topic, partition, high - start, start)
      end
    end

    def mark_all_treated
      ends = partitions.to_h { |partition| [ partition, Karafka::Admin.read_watermark_offsets(@topic, partition).last ] }
      Karafka::Admin.seek_consumer_group(@group, { @topic => ends })
    end
  end
end
