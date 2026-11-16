require "spec_helper"
require_relative "../karafka"

# Kafka real (serviço `kafka` do Compose): o webhook aceito tem de aparecer no tópico.
RSpec.describe "Webhook publicado no Kafka real" do
  let(:topic) { "test.broker.#{SecureRandom.hex(6)}" }
  let(:secret) { "segredo-do-broker" }
  let(:app) do
    Broker::WebhookApp.new(producer: Karafka.producer, secrets: [ secret ], allowed_topics: [ topic ],
                           logger: Logger.new(IO::NULL))
  end

  before { Karafka::Admin.create_topic(topic, 1, 1) }
  after { Karafka::Admin.delete_topic(topic) }

  def deliver(event_id:, seq:)
    body = { topic: topic, key: "ticket-1", headers: { "brand_id" => "jim", "event_id" => event_id },
             payload: { "seq" => seq } }.to_json
    timestamp = Time.now.to_i
    Rack::MockRequest.new(app).post(
      "/webhooks/helpdesk",
      input: body,
      "HTTP_X_WEBHOOK_ID" => event_id,
      "HTTP_X_WEBHOOK_TIMESTAMP" => timestamp.to_s,
      "HTTP_X_WEBHOOK_SIGNATURE" => Broker::Signature.sign(id: event_id, timestamp: timestamp, body: body, secret: secret)
    )
  end

  it "mantém a ordem das mensagens de um mesmo ticket, com chave e headers" do
    statuses = (1..3).map { |seq| deliver(event_id: "evt-#{seq}", seq: seq).status }

    messages = Karafka::Admin.read_topic(topic, 0, 10)

    expect(statuses).to eq([ 204, 204, 204 ])
    expect(messages.map(&:key)).to eq([ "ticket-1" ] * 3)
    expect(messages.map { |m| JSON.parse(m.raw_payload) }).to eq([ { "seq" => 1 }, { "seq" => 2 }, { "seq" => 3 } ])
    expect(messages.map { |m| m.headers["event_id"] }).to eq(%w[evt-1 evt-2 evt-3])
    expect(messages.map { |m| m.headers["brand_id"] }).to all(eq("jim"))
  end
end
