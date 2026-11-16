require "spec_helper"

RSpec.describe Broker::WebhookApp do
  let(:secret) { "segredo-do-broker" }
  # Produtor falso: registra o que recebeu e pode simular o Kafka fora do ar.
  let(:producer) do
    Class.new do
      attr_reader :sent
      attr_accessor :error

      def initialize
        @sent = []
      end

      def produce_sync(message)
        raise error if error

        @sent << message
      end
    end.new
  end
  let(:app) do
    described_class.new(producer: producer, secrets: [ secret ], allowed_topics: [ "helpdesk.messages" ],
                        logger: Logger.new(IO::NULL))
  end
  let(:event) do
    { topic: "helpdesk.messages", key: "ticket-1",
      headers: { "brand_id" => "jim", "event_id" => "evt-1" }, payload: { "seq" => 1 } }
  end

  def deliver(body = event.to_json, secret: self.secret, id: "evt-1", timestamp: Time.now.to_i, path: "/webhooks/helpdesk")
    Rack::MockRequest.new(app).post(
      path,
      input: body,
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_WEBHOOK_ID" => id,
      "HTTP_X_WEBHOOK_TIMESTAMP" => timestamp.to_s,
      "HTTP_X_WEBHOOK_SIGNATURE" => Broker::Signature.sign(id: id, timestamp: timestamp, body: body, secret: secret)
    )
  end

  it "publica o evento no Kafka com chave, headers e corpo, e responde 204" do
    response = deliver

    expect(response.status).to eq(204)
    expect(producer.sent).to eq([
      { topic: "helpdesk.messages", key: "ticket-1", payload: '{"seq":1}',
        headers: { "brand_id" => "jim", "event_id" => "evt-1" } }
    ])
  end

  it "recusa assinatura inválida sem publicar" do
    response = deliver(secret: "outro-segredo")

    expect(response.status).to eq(401)
    expect(producer.sent).to be_empty
  end

  it "recusa timestamp fora da tolerância" do
    expect(deliver(timestamp: Time.now.to_i - 301).status).to eq(401)
    expect(producer.sent).to be_empty
  end

  it "recusa tópico fora da lista permitida" do
    response = deliver(event.merge(topic: "outro.topico").to_json)

    expect(response.status).to eq(422)
    expect(producer.sent).to be_empty
  end

  it "recusa corpo malformado ou incompleto" do
    [ "não é json", "[]", event.except(:key).to_json, event.merge(payload: "texto").to_json,
      event.merge(headers: { "n" => 1 }).to_json ].each do |body|
      expect(deliver(body).status).to eq(422), "aceitou #{body}"
    end
    expect(producer.sent).to be_empty
  end

  it "responde 503 quando o Kafka não confirma, para a plataforma tentar de novo" do
    producer.error = WaterDrop::Errors::ProduceError.new("kafka fora")

    expect(deliver.status).to eq(503)
  end

  it "responde 200 em /up e 404 em rotas desconhecidas" do
    request = Rack::MockRequest.new(app)

    expect(request.get("/up").status).to eq(200)
    expect(request.get("/webhooks/helpdesk").status).to eq(404)
    expect(deliver(path: "/outra").status).to eq(404)
  end
end
