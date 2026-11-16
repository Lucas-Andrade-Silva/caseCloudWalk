require "rails_helper"

RSpec.describe "Entrada de canal (POST /webhooks/channels/:channel)" do
  before { create_brand }

  it "cria cliente, ticket, mensagem, linha do tempo e evento para o agente" do
    post_channel

    expect(response).to have_http_status(:created)
    ticket = Ticket.sole
    message = Message.sole
    expect(response.parsed_body).to eq(
      "ticket_id" => ticket.id, "message_id" => message.id, "seq" => 1, "duplicate" => false
    )
    expect(ticket).to have_attributes(channel: "whatsapp", mode: "ai", handoff_epoch: 0, last_seq: 1)
    expect(ticket.customer).to have_attributes(external_id: "cust-42", name: "Maria")
    expect(message).to have_attributes(seq: 1, sender: "customer", body: "minha maquininha não liga")
    expect(ConversationEvent.order(:id).pluck(:kind, :actor)).to eq(
      [ %w[ticket.opened customer], %w[message.received customer] ]
    )

    event = OutboxEvent.sole
    expect(event).to have_attributes(topic: "helpdesk.messages", key: ticket.id, headers: { "brand_id" => "infinitepay" })
    expect(event.payload).to include(
      "type" => "message.created", "ticket_id" => ticket.id, "brand" => "infinitepay",
      "channel" => "whatsapp", "mode" => "ai", "handoff_epoch" => 0
    )
    expect(event.payload["message"]).to include("id" => message.id, "seq" => 1, "sender" => "customer",
                                                "text" => "minha maquininha não liga")
    expect(event.payload["customer"]).to include("external_id" => "cust-42")
  end

  it "junta a segunda mensagem do mesmo cliente, marca e canal no mesmo ticket" do
    post_channel
    post_channel("whatsapp", channel_payload(provider_message_id: "wamid.2", text: "alguém aí?"))

    expect(Ticket.count).to eq(1)
    expect(Message.order(:seq).pluck(:seq, :body)).to eq([ [ 1, "minha maquininha não liga" ], [ 2, "alguém aí?" ] ])
    expect(ConversationEvent.where(kind: "ticket.opened").count).to eq(1)
    expect(OutboxEvent.count).to eq(2)
  end

  it "abre tickets separados para canais e marcas diferentes" do
    create_brand("jim")

    post_channel
    post_channel("email", channel_payload(provider_message_id: "mail.1"))
    post_channel("whatsapp", channel_payload(provider_message_id: "wamid.9", brand: "jim"))

    expect(Ticket.count).to eq(3)
    expect(Customer.count).to eq(2)
  end

  it "reconhece o webhook repetido e não cria nada de novo" do
    post_channel
    first = response.parsed_body

    post_channel

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first.merge("duplicate" => true))
    expect([ Ticket.count, Message.count, OutboxEvent.count ]).to eq([ 1, 1, 1 ])
  end

  it "trata o mesmo provider_message_id em canais diferentes como mensagens distintas" do
    post_channel("whatsapp")
    post_channel("email")

    expect(Message.count).to eq(2)
  end

  describe "assinatura" do
    it "recusa assinatura feita com outro segredo" do
      post_channel("whatsapp", channel_payload, secret: "segredo-errado")

      expect(response).to have_http_status(:unauthorized)
      expect([ Ticket.count, InboundEvent.count, OutboxEvent.count ]).to eq([ 0, 0, 0 ])
    end

    it "recusa timestamp fora da tolerância de 5 minutos" do
      post_channel("whatsapp", channel_payload, timestamp: Time.now.to_i - 301)

      expect(response).to have_http_status(:unauthorized)
      expect(Ticket.count).to eq(0)
    end

    it "recusa corpo alterado depois de assinado" do
      body = channel_payload.to_json
      headers = signed_headers(body)

      post "/webhooks/channels/whatsapp", params: body.sub("não liga", "explodiu"), headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "recusa requisição sem os headers de assinatura" do
      post "/webhooks/channels/whatsapp", params: channel_payload.to_json,
                                          headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "aceita qualquer segredo da lista, para permitir rotação" do
      allow(IntegrationConfig).to receive(:channel_webhook_secrets).and_return(%w[segredo-novo segredo-antigo])

      post_channel("whatsapp", channel_payload, secret: "segredo-antigo")

      expect(response).to have_http_status(:created)
    end
  end

  describe "validação" do
    it "recusa canal desconhecido" do
      post_channel("telegram")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "recusa marca desconhecida sem gravar nada" do
      post_channel("whatsapp", channel_payload(brand: "outra"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(InboundEvent.count).to eq(0)
    end

    it "recusa campos obrigatórios ausentes ou vazios" do
      [ { text: " " }, { provider_message_id: nil }, { customer: { external_id: "" } } ].each do |overrides|
        post_channel("whatsapp", channel_payload(overrides))

        expect(response).to have_http_status(:unprocessable_content), "aceitou #{overrides}"
      end
      expect(Ticket.count).to eq(0)
    end

    it "recusa corpo que não é JSON" do
      body = "isto não é json"
      post "/webhooks/channels/whatsapp", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
