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

    expect(reply["mean_seconds"]).to eq(2860) # média de 3 min, 20 min e 2 h
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

  it "mede o tempo de solução, da abertura ao fechamento, separado entre IA e humano" do
    by_ai = ticket_at("ia", now - 3.hours)
    close(by_ai, now - 2.hours, code: "ai_resolved")
    by_human = ticket_at("humano", now - 5.hours)
    close(by_human, now - 2.hours)
    by_human2 = ticket_at("humano-2", now - 2.hours)
    close(by_human2, now - 1.hour)

    resolution_time = dashboard("Ana")["resolution_time"]

    expect(resolution_time).to eq("median_seconds" => 3600, "ai_median_seconds" => 3600,
                                  "human_median_seconds" => 7200, "resolved" => 3)
  end

  it "mostra o desempenho de cada analista: resolvidos, resposta e SLA, e quem está atendendo agora" do
    bia = create_analyst("Bia")
    ana = User.find_by!(name: "Ana")
    done = escalate_and_answer(ticket_at("a1", now - 4.hours), escalated_at: now - 3.hours, answered_after: 10.minutes)
    done.update_columns(assignee_id: ana.id, first_response_due_at: now - 2.hours)
    close(done, now - 1.hour)
    working = escalate_and_answer(ticket_at("a2", now - 2.hours), escalated_at: now - 90.minutes, answered_after: 30.minutes)
    working.update_columns(assignee_id: ana.id, mode: "human", first_response_due_at: now - 80.minutes)

    team = dashboard("Olivia")["team"]

    expect(team["active"]).to eq(1)
    expect(team["total"]).to eq(2)
    expect(team["agents"]).to eq([
      { "id" => ana.id, "name" => "Ana", "resolved" => 1, "open" => 1, "reply_median_seconds" => 1200, "sla_percent" => 50 },
      { "id" => bia.id, "name" => "Bia", "resolved" => 0, "open" => 0, "reply_median_seconds" => nil, "sla_percent" => nil }
    ])
  end

  it "lista a operação dos tickets: parados há mais de 3 dias, sem analista e os que pedem gente" do
    ana = User.find_by!(name: "Ana")
    stale = ticket_at("parado", now - 4.days)
    waiting = escalate_and_answer(ticket_at("fila", now - 1.hour), escalated_at: now - 30.minutes)
    waiting.update_columns(priority: "p1")
    taken = escalate_and_answer(ticket_at("com-ana", now - 2.hours), escalated_at: now - 1.hour)
    taken.update_columns(assignee_id: ana.id, mode: "human", priority: "p2")

    operations = dashboard("Ana")["operations"]

    expect(operations["stale"]).to eq(1)
    expect(operations["unassigned"]).to eq(1)
    expect(operations["tickets"].map { |row| [ row["id"], row["agent"], row["agent_id"], row["priority"] ] }).to eq([
      [ waiting.id, nil, nil, "p1" ], [ taken.id, "Ana", ana.id, "p2" ]
    ])
    expect(operations["tickets"].first).to include("subject", "brand")
    expect(stale.reload.mode).to eq("ai")
  end

  it "sem token responde 401" do
    get "/api/dashboard"

    expect(response).to have_http_status(:unauthorized)
  end
end
