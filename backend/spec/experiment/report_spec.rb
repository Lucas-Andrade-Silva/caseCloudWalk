require "rails_helper"

RSpec.describe Experiment::Report do
  before { create_brand }

  it "percentil pelo posto mais próximo, sem média" do
    expect(described_class.percentile([ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], 0.5)).to eq(5)
    expect(described_class.percentile([ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], 0.99)).to eq(10)
    expect(described_class.percentile([], 0.5)).to be_nil
  end

  it "resume cada fase: ACK, ponta a ponta até a resposta do agente, escaladas e atraso do outbox" do
    base = Time.zone.parse("2026-11-23 10:00:00")
    answered = travel_to(base) { receive_message(provider_message_id: "k6-a", customer_external_id: "c-a").ticket }
    travel_to(base + 2.seconds) { answered.append_message!(sender: "bot", body: "oi") }
    OutboxEvent.where(key: answered.id).update_all(created_at: base, published_at: base + 0.3.seconds)
    # Evento do mesmo ticket muito depois, fora da janela da fase: não entra no atraso do outbox dela.
    OutboxEvent.create!(event_id: SecureRandom.uuid, topic: "agent.events", key: answered.id, payload: {},
                        created_at: base + 1.hour, published_at: base + 1.hour + 9.seconds)
    escalated = travel_to(base + 3.seconds) { escalated_ticket("c-b") }
    escalated_pmid = escalated.messages.first.inbound_event.provider_message_id
    ledger = [
      { "channel" => "whatsapp", "provider_message_id" => "k6-a", "status" => 201, "ack_ms" => 20.0, "stage" => "1x", "redelivery" => false, "offset_s" => 0.0 },
      { "channel" => "whatsapp", "provider_message_id" => "k6-a", "status" => 200, "ack_ms" => 5.0, "stage" => "1x", "redelivery" => true, "offset_s" => 2.0 },
      { "channel" => "whatsapp", "provider_message_id" => escalated_pmid, "status" => 201, "ack_ms" => 40.0, "stage" => "10x", "redelivery" => false },
      { "channel" => "whatsapp", "provider_message_id" => "k6-nunca", "status" => 503, "ack_ms" => 9.0, "stage" => "10x", "redelivery" => false }
    ]

    report = described_class.call(ledger: ledger)

    one, ten = report[:stages]
    expect(one).to include(stage: "1x", sent: 2, redeliveries: 1, rate_per_s: 0.5, refused: 0, ack_p50_ms: 5.0, ack_p99_ms: 20.0,
                           answered: 1, escalated: 0, e2e_p50_ms: 2000, e2e_p99_ms: 2000, outbox_p99_ms: 300)
    expect(ten).to include(stage: "10x", sent: 2, refused: 1, answered: 0, escalated: 1, e2e_p99_ms: nil)
    expect(report[:totals]).to include(sent: 4, unique_messages: 3)
  end
end
