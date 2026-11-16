require "rails_helper"

# Ida e volta completa: Postgres (outbox) -> relay -> Kafka real -> consumidor Karafka -> Postgres.
RSpec.describe "Ida e volta pelo Kafka com reentrega", :kafka do
  self.use_transactional_tests = false

  before do
    RoundTripTestConsumer.reset
    KarafkaEmbedded.start
  end

  after do
    OutboxEvent.delete_all
    ProcessedEvent.delete_all
  end

  it "consome o evento e aplica o efeito uma vez, mesmo com a mensagem duplicada" do
    event = OutboxEvent.create!(
      topic: KarafkaEmbedded::ROUND_TRIP_TOPIC,
      key: "conversation-1",
      payload: { "text" => "olá" }
    )
    relay = Outbox::Relay.new

    expect(relay.publish_pending).to eq(1)
    # Simula o relay caindo depois de publicar e antes de marcar: o evento sai de novo.
    OutboxEvent.where(id: event.id).update_all(published_at: nil)
    expect(relay.publish_pending).to eq(1)

    RoundTripTestConsumer.wait_for_deliveries(2, timeout: 60)

    expect(RoundTripTestConsumer.deliveries).to eq(2)
    expect(RoundTripTestConsumer.effects).to eq([ { "text" => "olá" } ])
    expect(ProcessedEvent.where(event_id: event.event_id).count).to eq(1)
  end
end
