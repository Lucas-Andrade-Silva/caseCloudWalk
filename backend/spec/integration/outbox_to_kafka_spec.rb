require "rails_helper"

# Kafka real (serviço `kafka` do Compose). Sem transação de teste: o relay grava de verdade.
RSpec.describe "Outbox publicado no Kafka real", :kafka do
  self.use_transactional_tests = false

  let(:topic) { KafkaTestTopics.create }

  after { OutboxEvent.delete_all }

  it "entrega os eventos de uma mesma chave em ordem, com chave, corpo e headers" do
    events = (1..3).map do |n|
      OutboxEvent.create!(
        topic: topic,
        key: "conversation-1",
        payload: { "seq" => n },
        headers: { "brand_id" => "infinitepay" }
      )
    end

    expect(Outbox::Relay.new.publish_pending).to eq(3)

    messages = Karafka::Admin.read_topic(topic, 0, 10)

    expect(messages.map(&:key)).to eq([ "conversation-1" ] * 3)
    expect(messages.map(&:payload)).to eq([ { "seq" => 1 }, { "seq" => 2 }, { "seq" => 3 } ])
    expect(messages.map { |m| m.headers["event_id"] }).to eq(events.map(&:event_id))
    expect(messages.map { |m| m.headers["brand_id"] }).to all(eq("infinitepay"))
  end
end
