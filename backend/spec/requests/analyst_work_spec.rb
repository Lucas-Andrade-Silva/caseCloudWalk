require "rails_helper"

RSpec.describe "Trabalho do analista" do
  let(:noon) { Time.zone.parse("2026-11-15 12:00:00") }
  let(:json) { { "CONTENT_TYPE" => "application/json" } }

  before do
    create_brand("infinitepay")
    create_brand("jim")
    create_bot
    create_analyst("Ana", brands: [ "infinitepay" ])
    create_analyst("Beto", brands: %w[infinitepay jim])
  end

  describe "POST /api/work/next" do
    it "entrega o ticket de prazo mais próximo das filas do analista e o deixa com ele" do
      travel_to(noon)
      normal = escalated_ticket("c-normal", priority: "p3") # prazo 13:00
      travel_to(noon + 30.minutes)
      high = escalated_ticket("c-alta", priority: "p2") # prazo 12:45
      urgent_jim = escalated_ticket("c-jim", brand: "jim", priority: "p1") # prazo 12:35, fora das filas da Ana

      post "/api/work/next", headers: auth_as("Ana")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => high.id, "mode" => "human", "priority" => "p2")
      expect(high.reload).to have_attributes(mode: "human", assignee: User.find_by!(name: "Ana"), handoff_epoch: 2)
      assigned = high.conversation_events.order(:id).last
      expect(assigned).to have_attributes(kind: "ticket.assigned", actor: "analyst")
      expect(assigned.data).to include("trigger" => "work_next", "waited_seconds" => 0)

      post "/api/work/next", headers: auth_as("Ana")
      expect(response.parsed_body["id"]).to eq(normal.id)

      post "/api/work/next", headers: auth_as("Ana")
      expect(response).to have_http_status(:no_content)
      expect(urgent_jim.reload.mode).to eq("pending_human")
    end

    it "exige um analista" do
      post "/api/work/next"
      expect(response).to have_http_status(:unauthorized)

      post "/api/work/next", headers: { "Authorization" => "Bearer #{DomainHelpers::BOT_TOKEN}" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/tickets/:id/takeover" do
    let(:ticket) { receive_message.ticket }

    it "assume um ticket que está com a IA e descarta a resposta atrasada do bot" do
      post "/api/tickets/#{ticket.id}/takeover", headers: auth_as("Ana")

      expect(response).to have_http_status(:ok)
      expect(ticket.reload).to have_attributes(
        mode: "human", assignee: User.find_by!(name: "Ana"), handoff_epoch: 1, queue: default_queue,
        escalation_trigger: "analyst_takeover"
      )
      expect(ticket.handoff_brief).to include("trigger" => "analyst_takeover")
      expect(ticket.conversation_events.order(:id).pluck(:kind).last(2)).to eq(%w[ticket.escalated ticket.assigned])

      post "/api/agent/replies", headers: json.merge("Authorization" => "Bearer #{DomainHelpers::BOT_TOKEN}"),
                                 params: { agent_turn_id: SecureRandom.uuid, ticket_id: ticket.id, in_reply_to_seq: 1,
                                           handoff_epoch: 0, action: "reply", text: "Oi!" }.to_json
      expect(response).to have_http_status(:conflict)
    end

    it "não deixa assumir ticket de marca que o analista não atende" do
      jim = receive_message(provider_message_id: "wamid.jim", brand_slug: "jim").ticket

      post "/api/tickets/#{jim.id}/takeover", headers: auth_as("Ana")

      expect(response).to have_http_status(:not_found)
      expect(jim.reload.mode).to eq("ai")
    end

    it "recusa assumir ticket que já saiu da IA" do
      pending = escalated_ticket("c-1")

      post "/api/tickets/#{pending.id}/takeover", headers: auth_as("Ana")

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "mensagens e fechamento" do
    let(:ticket) do
      travel_to(noon)
      escalated_ticket("c-1", priority: "p2") # prazo 12:15
    end

    def take(name = "Ana")
      ticket
      post "/api/work/next", headers: auth_as(name)
    end

    def say(text, as: "Ana")
      post "/api/tickets/#{ticket.id}/messages", params: { text: text }.to_json, headers: json.merge(auth_as(as))
    end

    it "grava a mensagem do dono e registra o SLA cumprido na primeira resposta" do
      take
      travel_to(noon + 10.minutes)

      say("Oi, Maria, sou a Ana.")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("seq" => 2, "sla_met" => true)
      expect(ticket.reload.first_human_response_at).to eq(noon + 10.minutes)
      event = ticket.conversation_events.order(:id).last
      expect(event).to have_attributes(kind: "message.sent", actor: "analyst")
      expect(event.data).to include("first_response" => true, "sla_met" => true)

      travel_to(noon + 20.minutes)
      say("Resolvido?")
      expect(response.parsed_body).to include("seq" => 3, "sla_met" => nil)
      expect(ticket.reload.first_human_response_at).to eq(noon + 10.minutes)
    end

    it "registra o SLA estourado quando a primeira resposta passa do prazo" do
      take
      travel_to(noon + 16.minutes)

      say("Desculpe a demora.")

      expect(response.parsed_body["sla_met"]).to be(false)
    end

    it "só o dono escreve e fecha" do
      take

      say("Eu também!", as: "Beto")
      expect(response).to have_http_status(:forbidden)

      post "/api/tickets/#{ticket.id}/close", headers: auth_as("Beto")
      expect(response).to have_http_status(:forbidden)
      expect(ticket.reload.mode).to eq("human")
    end

    it "fecha o ticket e não deixa fechar de novo" do
      take

      post "/api/tickets/#{ticket.id}/close", headers: auth_as("Ana")
      expect(response).to have_http_status(:ok)
      expect(ticket.reload.mode).to eq("closed")
      expect(ticket.conversation_events.order(:id).last.kind).to eq("ticket.closed")

      post "/api/tickets/#{ticket.id}/close", headers: auth_as("Ana")
      expect(response).to have_http_status(:conflict)
    end

    it "recusa mensagem vazia" do
      take

      say("  ")

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/tickets/:id" do
    it "mostra ticket, brief, mensagens e linha do tempo para quem atende a marca" do
      ticket = escalated_ticket("c-1")

      get "/api/tickets/#{ticket.id}", headers: auth_as("Ana")

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("id" => ticket.id, "mode" => "pending_human", "brand" => "infinitepay",
                              "queue" => "infinitepay-atendimento", "priority" => "p3")
      expect(body["handoff_brief"]).to include("reason" => "teste")
      expect(body["messages"].map { |m| [ m["seq"], m["sender"] ] }).to eq([ [ 1, "customer" ] ])
      expect(body["events"].map { |e| e["kind"] }).to eq(%w[ticket.opened message.received ticket.escalated])
    end

    it "esconde ticket de marca que o analista não atende" do
      ticket = escalated_ticket("c-jim", brand: "jim")

      get "/api/tickets/#{ticket.id}", headers: auth_as("Ana")

      expect(response).to have_http_status(:not_found)
    end
  end
end
