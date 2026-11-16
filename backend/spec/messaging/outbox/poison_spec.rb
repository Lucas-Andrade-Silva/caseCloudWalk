require "rails_helper"

RSpec.describe "Outbox com evento envenenado" do
  # Produtor falso: recusa de vez as chaves de `rejected` e falha temporariamente nas de `unavailable`.
  let(:producer) do
    Class.new do
      attr_reader :sent
      attr_accessor :rejected, :unavailable

      def initialize
        @sent = []
        @rejected = []
        @unavailable = []
      end

      def produce_sync(message)
        raise Outbox::WebhookPublisher::Rejected, "broker respondeu 422" if rejected.include?(message[:payload])
        raise Outbox::WebhookPublisher::DeliveryError, "broker respondeu 503" if unavailable.include?(message[:payload])

        @sent << message[:payload]
      end
    end.new
  end
  let(:relay) { Outbox::Relay.new(producer: producer) }

  def enqueue(name, key)
    OutboxEvent.create!(topic: "helpdesk.messages", key: key, payload: { "n" => name })
  end

  def sent_names = producer.sent.map { |payload| JSON.parse(payload)["n"] }

  it "estaciona o evento recusado e segue com os de outros tickets" do
    enqueue("a", "ticket-x")
    poisoned = enqueue("b", "ticket-y")
    held = enqueue("c", "ticket-y")
    enqueue("d", "ticket-z")
    producer.rejected = [ { "n" => "b" }.to_json ]

    expect(relay.publish_pending).to eq(2)

    expect(sent_names).to eq(%w[a d])
    expect(poisoned.reload).to have_attributes(dead_at: be_present, attempts: 1, last_error: /422/)
    expect(held.reload).to have_attributes(published_at: nil, dead_at: nil)
    expect(OutboxEvent.pending).to be_empty
    expect(OutboxEvent.dead).to eq([ poisoned ])
  end

  it "retém os próximos eventos do ticket estacionado, também nas rodadas seguintes" do
    enqueue("b", "ticket-y")
    producer.rejected = [ { "n" => "b" }.to_json ]
    relay.publish_pending

    enqueue("c", "ticket-y")
    enqueue("d", "ticket-z")

    relay.publish_pending
    expect(sent_names).to eq(%w[d])
  end

  it "devolve a ordem do ticket quando o estacionado é reenviado" do
    poisoned = enqueue("b", "ticket-y")
    enqueue("c", "ticket-y")
    producer.rejected = [ { "n" => "b" }.to_json ]
    relay.publish_pending

    producer.rejected = []
    poisoned.retry!

    expect(relay.publish_pending).to eq(2)
    expect(sent_names).to eq(%w[b c])
    expect(poisoned.reload).to have_attributes(published_at: be_present, dead_at: nil)
  end

  it "libera o ticket quando o estacionado é descartado" do
    poisoned = enqueue("b", "ticket-y")
    enqueue("c", "ticket-y")
    producer.rejected = [ { "n" => "b" }.to_json ]
    relay.publish_pending

    poisoned.discard!

    expect(relay.publish_pending).to eq(1)
    expect(sent_names).to eq(%w[c])
    expect(OutboxEvent.dead).to be_empty
    expect(poisoned.reload.discarded_at).to be_present
  end

  it "não estaciona em falha temporária: conta a tentativa, guarda o erro e para o lote" do
    event = enqueue("b", "ticket-y")
    enqueue("d", "ticket-z")
    producer.unavailable = [ { "n" => "b" }.to_json ]

    expect { relay.publish_pending }.to raise_error(Outbox::WebhookPublisher::DeliveryError)

    expect(event.reload).to have_attributes(dead_at: nil, attempts: 1, last_error: /503/)
    expect(sent_names).to be_empty
  end
end
