require "rails_helper"

RSpec.describe "Simulador de canal (/api/simulator)" do
  let(:json) { { "CONTENT_TYPE" => "application/json" } }
  let(:maria) { { brand: "infinitepay", channel: "app_chat", customer: { external_id: "sim-maria", name: "Maria" } } }

  before { create_brand }

  context "com o simulador ligado" do
    around do |example|
      ENV["CHANNEL_SIMULATOR_ENABLED"] = "true"
      example.run
    ensure
      ENV.delete("CHANNEL_SIMULATOR_ENABLED")
    end

    it "envia a mensagem do cliente pela ingestão e devolve a conversa com a resposta" do
      post "/api/simulator/messages", params: maria.merge(text: "minha maquininha não liga").to_json, headers: json

      expect(response).to have_http_status(:created)
      ticket = Ticket.sole
      expect(response.parsed_body).to include("ticket_id" => ticket.id, "seq" => 1)
      expect(ticket).to have_attributes(channel: "app_chat", mode: "ai")
      expect(ticket.customer).to have_attributes(external_id: "sim-maria", name: "Maria")
      expect(OutboxEvent.sole.payload["type"]).to eq("message.created")
      expect(InboundEvent.sole.payload).to include("source" => "simulator")

      ticket.append_message!(sender: "bot", body: "Já vou te ajudar.", in_reply_to_seq: 1)
      get "/api/simulator/conversation", params: { brand: "infinitepay", channel: "app_chat", external_id: "sim-maria" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ticket_id" => ticket.id, "mode" => "ai")
      expect(response.parsed_body["messages"].map { |m| [ m["seq"], m["sender"], m["text"] ] })
        .to eq([ [ 1, "customer", "minha maquininha não liga" ], [ 2, "bot", "Já vou te ajudar." ] ])
    end

    it "mostra o atendimento mais recente do canal, mesmo encerrado, e nada para cliente novo" do
      post "/api/simulator/messages", params: maria.merge(text: "oi").to_json, headers: json
      Ticket.sole.update!(mode: "closed", closed_at: Time.current, resolution_code: "resolved")

      get "/api/simulator/conversation", params: { brand: "infinitepay", channel: "app_chat", external_id: "sim-maria" }
      expect(response.parsed_body).to include("mode" => "closed")

      get "/api/simulator/conversation", params: { brand: "infinitepay", channel: "app_chat", external_id: "ninguem" }
      expect(response.parsed_body).to eq("ticket_id" => nil, "mode" => nil, "messages" => [])
    end

    it "recusa mensagem inválida com o motivo" do
      post "/api/simulator/messages", params: maria.merge(text: " ").to_json, headers: json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("text é obrigatório")
      expect(Ticket.count).to eq(0)
    end
  end

  it "não existe com o simulador desligado" do
    post "/api/simulator/messages", params: maria.merge(text: "oi").to_json, headers: json
    expect(response).to have_http_status(:not_found)

    get "/api/simulator/conversation", params: { brand: "infinitepay", channel: "app_chat", external_id: "sim-maria" }
    expect(response).to have_http_status(:not_found)
    expect(Ticket.count).to eq(0)
  end
end
