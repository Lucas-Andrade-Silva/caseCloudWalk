require "rails_helper"

RSpec.describe "Painel" do
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:now) { zone.parse("2026-11-22 15:00") }

  before do
    create_brand
    create_brand("jim")
    create_analyst("Ana")
    User.create!(name: "Olivia", role: "ops", token_digest: User.digest("token-de-olivia"))
  end

  def ticket_at(customer, at, brand: "infinitepay", channel: "whatsapp")
    travel_to(at) do
      receive_message(channel: channel, provider_message_id: "wamid.#{customer}", customer_external_id: customer,
                      brand_slug: brand).ticket
    end
  end

  def escalate_and_answer(ticket, escalated_at:, answered_after: nil)
    travel_to(escalated_at) do
      ticket.with_lock { Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: "teste", actor: "bot") }
    end
    ticket.update!(first_human_response_at: escalated_at + answered_after) if answered_after
    ticket
  end

  def close(ticket, at, code: "resolved")
    ticket.update_columns(mode: "closed", closed_at: at, resolution_code: code)
  end

  def dashboard(as)
    travel_to(now) { get "/api/dashboard", headers: auth_as(as) }
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it "conta o que está aberto agora, criados e resolvidos hoje contra ontem, e a série dos últimos 7 dias" do
    ticket_at("hoje-1", now - 2.hours)
    ticket_at("hoje-2", now - 1.hour, channel: "email")
    yesterday = ticket_at("ontem", now - 1.day)
    close(yesterday, now - 1.day + 10.minutes)
    old = ticket_at("velho", now - 3.days)
    close(old, now - 30.minutes, code: "ai_resolved")
    ticket_at("fora", now - 10.days)

    body = dashboard("Ana")

    expect(body["open"]).to include("total" => 3, "ai" => 3, "pending_human" => 0, "human" => 0)
    expect(body["today"]).to eq("created" => 2, "closed" => 1)
    expect(body["yesterday"]).to eq("created" => 1, "closed" => 1)
    expect(body["daily"].size).to eq(7)
    expect(body["daily"].last).to eq("date" => "2026-11-22", "created" => 2, "closed" => 1)
    expect(body["daily"].first["date"]).to eq("2026-11-16")
    expect(body["channels"]).to contain_exactly({ "channel" => "whatsapp", "count" => 3 }, { "channel" => "email", "count" => 1 })
    expect(body["resolution"]).to eq("ai" => 1, "human" => 1)
  end

  it "mede a primeira resposta humana e o SLA dos escalados na janela" do
    fast = escalate_and_answer(ticket_at("rapido", now - 3.hours), escalated_at: now - 3.hours, answered_after: 3.minutes)
    escalate_and_answer(ticket_at("medio", now - 3.hours), escalated_at: now - 3.hours, answered_after: 20.minutes)
    escalate_and_answer(ticket_at("lento", now - 5.hours), escalated_at: now - 5.hours, answered_after: 2.hours)
    escalate_and_answer(ticket_at("esperando", now - 4.hours), escalated_at: now - 4.hours)
    fast.update!(priority: "p3")

    reply = dashboard("Ana")["first_reply"]

    expect(reply["median_seconds"]).to eq(20 * 60)
    expect(reply["buckets"]).to eq([
      { "key" => "up_to_5m", "count" => 1 }, { "key" => "5m_to_15m", "count" => 0 },
      { "key" => "15m_to_1h", "count" => 1 }, { "key" => "over_1h", "count" => 1 },
      { "key" => "waiting", "count" => 1 }
    ])
    sla = dashboard("Ana")["sla"]
    expect(sla["met"] + sla["missed"]).to eq(4)
    expect(sla["missed"]).to be >= 2
  end

  it "o analista vê só as marcas que atende; a operação vê todas" do
    ticket_at("ip", now - 1.hour)
    ticket_at("jim", now - 1.hour, brand: "jim")

    expect(dashboard("Ana")["open"]["total"]).to eq(1)
    expect(dashboard("Olivia")["open"]["total"]).to eq(2)
  end

  it "conta os incidentes abertos" do
    tickets = Array.new(5) { |index| ticket_at("c-#{index}", now - 5.minutes) }
    travel_to(now) do
      tickets.each { |ticket| ticket.update!(llm_facts: { "category" => "maquininha" }) }
      Incidents::Detect.call(tickets.last)
    end

    expect(dashboard("Ana")["open"]["incidents"]).to eq(1)
  end

  it "sem token responde 401" do
    get "/api/dashboard"

    expect(response).to have_http_status(:unauthorized)
  end
end
