require "rails_helper"

RSpec.describe "Pedido de escalação do agente (POST /api/agent/replies, action escalate)" do
  let(:ticket) { receive_message.ticket }
  let(:auth) { { "Authorization" => "Bearer #{DomainHelpers::BOT_TOKEN}", "CONTENT_TYPE" => "application/json" } }

  before do
    create_brand
    create_bot
  end

  def escalation(overrides = {})
    {
      agent_turn_id: SecureRandom.uuid, ticket_id: ticket.id, in_reply_to_seq: 1, handoff_epoch: 0,
      action: "escalate", reason: "precisa_estorno", text: "Vou te passar para um especialista."
    }.merge(overrides)
  end

  def post_agent(payload)
    post "/api/agent/replies", params: payload.to_json, headers: auth
  end

  it "grava a despedida do bot e passa o ticket para a fila humana" do
    post_agent(escalation)

    expect(response).to have_http_status(:created)
    goodbye = Message.find_by!(sender: "bot")
    expect(response.parsed_body).to eq(
      "escalated" => true, "duplicate" => false, "message_id" => goodbye.id, "seq" => 2
    )
    expect(goodbye.body).to eq("Vou te passar para um especialista.")
    expect(ticket.reload).to have_attributes(mode: "pending_human", handoff_epoch: 1, queue: default_queue)
    expect(ticket.conversation_events.order(:id).pluck(:kind).last(2)).to eq(%w[message.sent ticket.escalated])
  end

  it "escala sem mensagem de despedida quando o texto não vem" do
    post_agent(escalation.except(:text))

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("escalated" => true, "message_id" => nil, "seq" => nil)
    expect(Message.where(sender: "bot")).to be_empty
    expect(ticket.reload.mode).to eq("pending_human")
  end

  it "não repete o efeito quando o mesmo pedido chega de novo" do
    payload = escalation
    post_agent(payload)

    post_agent(payload)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("escalated" => true, "duplicate" => true)
    expect(ConversationEvent.where(kind: "ticket.escalated").count).to eq(1)
    expect(ticket.reload.handoff_epoch).to eq(1)
  end

  it "descarta a resposta do bot que chega depois da escalação" do
    post_agent(escalation)

    post_agent(escalation(action: "reply", reason: nil, text: "Ainda estou aqui"))

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["reason"]).to eq("ticket_not_in_ai_mode")
    expect(Message.where(sender: "bot").count).to eq(1)
  end

  it "não envia ao agente as mensagens do cliente depois da escalação" do
    post_agent(escalation)
    agent_messages = -> { OutboxEvent.where("payload->>'type' = 'message.created'").count }

    expect { receive_message(provider_message_id: "wamid.2", text: "e aí?") }.not_to change(&agent_messages)
  end

  it "recusa pedido sem motivo ou com motivo fora do formato" do
    [ { reason: nil }, { reason: "" }, { reason: "Motivo Livre!" }, { reason: "x" * 65 } ].each do |overrides|
      post_agent(escalation(overrides))

      expect(response).to have_http_status(:unprocessable_content), "aceitou #{overrides}"
    end
    expect(ticket.reload.mode).to eq("ai")
  end
end
