require "rails_helper"

RSpec.describe "Resposta do agente (POST /api/agent/replies)" do
  let(:ticket) { receive_message.ticket }
  let(:auth) { { "Authorization" => "Bearer #{DomainHelpers::BOT_TOKEN}" } }

  before do
    create_brand
    create_bot
  end

  def reply_payload(overrides = {})
    {
      agent_turn_id: SecureRandom.uuid,
      ticket_id: ticket.id,
      in_reply_to_seq: 1,
      handoff_epoch: 0,
      action: "reply",
      text: "Olá, Maria. Vamos resolver isso."
    }.merge(overrides)
  end

  def post_reply(payload = reply_payload, headers: auth)
    post "/api/agent/replies", params: payload.to_json, headers: headers.merge("CONTENT_TYPE" => "application/json")
  end

  it "grava a resposta como mensagem do bot, com o próximo seq, e registra na linha do tempo" do
    payload = reply_payload

    post_reply(payload)

    expect(response).to have_http_status(:created)
    message = Message.find_by!(sender: "bot")
    expect(response.parsed_body).to eq(
      "message_id" => message.id, "seq" => 2, "stale" => false, "duplicate" => false
    )
    expect(message).to have_attributes(
      seq: 2, body: "Olá, Maria. Vamos resolver isso.", in_reply_to_seq: 1,
      agent_turn_id: payload[:agent_turn_id], stale: false, ticket_id: ticket.id
    )
    event = ConversationEvent.order(:id).last
    expect(event).to have_attributes(kind: "message.sent", actor: "bot")
    expect(event.data).to include("message_id" => message.id, "seq" => 2, "stale" => false)
  end

  it "não repete o efeito quando o mesmo agent_turn_id chega de novo" do
    payload = reply_payload
    post_reply(payload)
    first = response.parsed_body

    post_reply(payload)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first.merge("duplicate" => true))
    expect(Message.where(sender: "bot").count).to eq(1)
    expect(ConversationEvent.where(kind: "message.sent").count).to eq(1)
  end

  it "entrega e sinaliza a resposta atrasada, quando o cliente já mandou outra mensagem" do
    ticket
    receive_message(provider_message_id: "wamid.2", text: "alguém aí?")

    post_reply(reply_payload(in_reply_to_seq: 1))

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("seq" => 3, "stale" => true)
    expect(Message.find_by!(sender: "bot").stale).to be(true)
    expect(ConversationEvent.order(:id).last.data).to include("stale" => true)
  end

  describe "descarte" do
    it "descarta e audita a resposta quando o ticket não está em modo ai" do
      ticket.update!(mode: "human", handoff_epoch: 1)
      payload = reply_payload(handoff_epoch: 1)

      post_reply(payload)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("discarded" => true, "reason" => "ticket_not_in_ai_mode")
      expect(Message.where(sender: "bot")).to be_empty
      event = ConversationEvent.order(:id).last
      expect(event).to have_attributes(kind: "reply.discarded", actor: "bot")
      expect(event.data).to include("agent_turn_id" => payload[:agent_turn_id], "reason" => "ticket_not_in_ai_mode")
    end

    it "descarta e audita a resposta com handoff_epoch diferente" do
      post_reply(reply_payload(handoff_epoch: 7))

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["reason"]).to eq("handoff_epoch_mismatch")
      expect(Message.where(sender: "bot")).to be_empty
    end

    it "audita o descarte uma vez só, mesmo com a resposta repetida" do
      payload = reply_payload(handoff_epoch: 7)

      2.times { post_reply(payload) }

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["reason"]).to eq("handoff_epoch_mismatch")
      expect(ConversationEvent.where(kind: "reply.discarded").count).to eq(1)
    end
  end

  describe "autenticação" do
    it "recusa requisição sem token" do
      post_reply(reply_payload, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "recusa token desconhecido" do
      post_reply(reply_payload, headers: { "Authorization" => "Bearer errado" })

      expect(response).to have_http_status(:unauthorized)
      expect(Message.where(sender: "bot")).to be_empty
    end

    it "recusa usuário que não é o bot" do
      User.create!(name: "Ana", role: "analyst", token_digest: User.digest("token-da-ana"))

      post_reply(reply_payload, headers: { "Authorization" => "Bearer token-da-ana" })

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "validação" do
    it "responde 404 para ticket inexistente" do
      post_reply(reply_payload(ticket_id: SecureRandom.uuid))

      expect(response).to have_http_status(:not_found)
    end

    it "recusa resposta a uma mensagem que não existe ou não é do cliente" do
      post_reply(reply_payload(in_reply_to_seq: 9))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "recusa campos ausentes, texto vazio, ação desconhecida e agent_turn_id que não é UUID" do
      [ { text: "" }, { action: "transfer_money" }, { agent_turn_id: "abc" }, { in_reply_to_seq: nil },
        { handoff_epoch: nil } ].each do |overrides|
        post_reply(reply_payload(overrides))

        expect(response).to have_http_status(:unprocessable_content), "aceitou #{overrides}"
      end
      expect(Message.where(sender: "bot")).to be_empty
    end
  end
end
