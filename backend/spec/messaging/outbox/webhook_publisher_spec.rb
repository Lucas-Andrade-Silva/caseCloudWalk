require "rails_helper"

RSpec.describe Outbox::WebhookPublisher do
  let(:requests) { [] }
  let(:status) { [ 204 ] }
  # Transporte falso: registra a requisição e devolve o próximo status do roteiro.
  let(:transport) do
    lambda do |uri, headers, body|
      requests << { uri: uri, headers: headers, body: body }
      status.first
    end
  end
  let(:publisher) do
    described_class.new(url: "http://broker:4000/webhooks/helpdesk", secret: "segredo-do-broker", transport: transport)
  end
  let(:message) do
    { topic: "helpdesk.messages", key: "ticket-1", payload: { "seq" => 1 }.to_json,
      headers: { "brand_id" => "jim", "event_id" => "0193-evt" } }
  end

  it "entrega o evento como webhook assinado, com o event_id como id do webhook" do
    publisher.produce_sync(message)

    request = requests.sole
    expect(request[:uri].to_s).to eq("http://broker:4000/webhooks/helpdesk")
    expect(JSON.parse(request[:body])).to eq(
      "topic" => "helpdesk.messages", "key" => "ticket-1",
      "headers" => { "brand_id" => "jim", "event_id" => "0193-evt" }, "payload" => { "seq" => 1 }
    )
    headers = request[:headers]
    expect(headers["X-Webhook-Id"]).to eq("0193-evt")
    expect(headers["Content-Type"]).to eq("application/json")
    expect(
      Webhooks::Signature.valid?(
        id: headers["X-Webhook-Id"], timestamp: headers["X-Webhook-Timestamp"], body: request[:body],
        signature: headers["X-Webhook-Signature"], secrets: [ "segredo-do-broker" ]
      )
    ).to be(true)
  end

  it "levanta erro quando o broker não responde 2xx, para o relay tentar de novo" do
    status[0] = 503

    expect { publisher.produce_sync(message) }.to raise_error(Outbox::WebhookPublisher::DeliveryError, /503/)
  end

  it "separa a recusa definitiva da falha temporária" do
    [ 400, 404, 413, 422 ].each do |code|
      status[0] = code
      expect { publisher.produce_sync(message) }.to raise_error(Outbox::WebhookPublisher::Rejected, /#{code}/)
    end

    [ 401, 403, 408, 429, 500, 503 ].each do |code|
      status[0] = code
      expect { publisher.produce_sync(message) }.to raise_error { |error|
        expect(error).to be_a(Outbox::WebhookPublisher::DeliveryError)
        expect(error).not_to be_a(Outbox::WebhookPublisher::Rejected)
      }
    end
  end

  it "deixa o evento pendente no outbox quando a entrega falha" do
    status[0] = 500
    event = OutboxEvent.create!(topic: "helpdesk.messages", key: "ticket-1", payload: { "seq" => 1 })

    expect { Outbox::Relay.new(producer: publisher).publish_pending }
      .to raise_error(Outbox::WebhookPublisher::DeliveryError)

    expect(event.reload.published_at).to be_nil
  end
end
