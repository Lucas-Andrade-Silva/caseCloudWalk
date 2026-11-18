require "rails_helper"

RSpec.describe Outbox::Relay do
  # Produtor falso: grava o que recebeu e pode falhar numa mensagem escolhida.
  let(:producer) do
    Class.new do
      attr_reader :sent
      attr_accessor :fail_on_key

      def initialize
        @sent = []
      end

      def produce_sync(message)
        raise "kafka indisponível" if message[:key] == fail_on_key

        @sent << message
      end
    end.new
  end

  let(:relay) { described_class.new(producer: producer) }

  def enqueue(key:, payload: { "n" => key }, headers: {})
    OutboxEvent.create!(topic: "test.topic", key: key, payload: payload, headers: headers)
  end

  it "publica os eventos pendentes em ordem de id e marca cada um como publicado" do
    events = [
      enqueue(key: "a", headers: { "brand_id" => "infinitepay" }),
      enqueue(key: "b"),
      enqueue(key: "c")
    ]

    expect(relay.publish_pending).to eq(3)

    expect(producer.sent.map { |m| m[:key] }).to eq(%w[a b c])
    # Toda entrega leva o contexto W3C do span de entrega (ADR 0008, O2); os demais headers seguem exatos.
    expect(producer.sent.first).to match(
      topic: "test.topic",
      key: "a",
      payload: { "n" => "a" }.to_json,
      headers: { "brand_id" => "infinitepay", "event_id" => events.first.event_id,
                 "traceparent" => a_string_matching(/\A00-\h{32}-\h{16}-0[01]\z/) }
    )
    expect(OutboxEvent.pending).to be_empty
    expect(events.map { |e| e.reload.published_at }).to all(be_present)
  end

  it "não republica o que já foi publicado" do
    enqueue(key: "a")
    relay.publish_pending
    producer.sent.clear

    expect(relay.publish_pending).to eq(0)
    expect(producer.sent).to be_empty
  end

  it "respeita o tamanho do lote e continua de onde parou" do
    %w[a b c].each { |key| enqueue(key: key) }
    relay = described_class.new(producer: producer, batch_size: 2)

    expect(relay.publish_pending).to eq(2)
    expect(relay.publish_pending).to eq(1)
    expect(producer.sent.map { |m| m[:key] }).to eq(%w[a b c])
  end

  it "quando falha no meio do lote, marca só o que saiu e retoma em ordem" do
    first, second, third = %w[a b c].map { |key| enqueue(key: key) }
    producer.fail_on_key = "b"

    expect { relay.publish_pending }.to raise_error("kafka indisponível")

    expect(first.reload.published_at).to be_present
    expect(second.reload.published_at).to be_nil
    expect(third.reload.published_at).to be_nil

    producer.fail_on_key = nil
    expect(relay.publish_pending).to eq(2)
    expect(producer.sent.map { |m| m[:key] }).to eq(%w[a b c])
  end

  it "dá a cada evento um event_id próprio" do
    ids = [ enqueue(key: "a"), enqueue(key: "b") ].map(&:event_id)

    expect(ids.uniq.size).to eq(2)
    expect(ids).to all(match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/))
  end
end
