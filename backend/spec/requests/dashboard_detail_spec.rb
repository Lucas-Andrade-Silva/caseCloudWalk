require "rails_helper"

# Telas de detalhe dos cards da tela inicial (ADR 0011): desempenho de um analista e tempo de solução.
RSpec.describe "Painel, detalhes" do
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:now) { zone.parse("2026-11-22 15:00") }
  let(:ana) { User.find_by!(name: "Ana") }

  before do
    create_brand
    create_brand("jim")
    create_analyst("Ana")
    User.create!(name: "Olivia", role: "ops", token_digest: User.digest("token-de-olivia"))
  end

  def ticket_at(customer, at, brand: "infinitepay")
    travel_to(at) do
      receive_message(channel: "whatsapp", provider_message_id: "wamid.#{customer}", customer_external_id: customer,
                      brand_slug: brand).ticket
    end
  end

  def escalate(ticket, at:, answered_after: nil, due: nil, agent: nil, category: nil, mode: "human")
    travel_to(at) do
      ticket.with_lock { Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: "teste", actor: "bot") }
    end
    ticket.update_columns(first_human_response_at: (at + answered_after if answered_after), first_response_due_at: due,
                          assignee_id: agent&.id, mode: mode, llm_facts: category ? { "category" => category } : {})
    ticket
  end

  def close(ticket, at, code: "resolved", agent: nil, category: nil)
    ticket.update_columns(mode: "closed", closed_at: at, resolution_code: code, assignee_id: agent&.id,
                          llm_facts: category ? { "category" => category } : {})
    ticket
  end

  def analyst_message(ticket, at)
    ticket.messages.create!(brand_id: ticket.brand_id, seq: ticket.last_seq + 1, sender: "analyst", body: "oi", created_at: at)
    ticket.update_columns(last_seq: ticket.last_seq + 1)
  end

  def get_as(name, path)
    travel_to(now) { get path, headers: auth_as(name) }
    response.parsed_body
  end

  describe "GET /api/dashboard/analysts/:id" do
    it "detalha o analista: recebidos, respondidos, resolvidos, SLA, assuntos mais tratados e a série diária" do
      resolved = escalate(ticket_at("a1", now - 4.hours), at: now - 3.hours, answered_after: 10.minutes, due: now - 2.hours,
                                                          agent: ana, category: "maquininha")
      close(resolved, now - 1.hour, agent: ana, category: "maquininha")
      analyst_message(resolved, now - 2.hours)
      working = escalate(ticket_at("a2", now - 2.hours), at: now - 90.minutes, answered_after: 30.minutes, due: now - 80.minutes,
                                                         agent: ana, category: "pix")
      analyst_message(working, now - 1.hour)
      escalate(ticket_at("a3", now - 1.hour), at: now - 1.hour, agent: ana, category: "maquininha")
      other = create_analyst("Bia")
      escalate(ticket_at("b1", now - 1.hour), at: now - 1.hour, agent: other, category: "pix")

      body = get_as("Olivia", "/api/dashboard/analysts/#{ana.id}")

      expect(body["agent"]).to eq("id" => ana.id, "name" => "Ana", "brands" => [ "infinitepay" ])
      expect(body).to include("received" => 3, "answered" => 2, "resolved" => 1, "open" => 2, "messages_sent" => 2)
      expect(body["first_reply"]).to eq("mean_seconds" => 1200, "answered" => 2)
      expect(body["sla"]).to eq("met" => 1, "missed" => 1, "percent" => 50)
      expect(body["resolution_time"]).to eq("mean_seconds" => 10_800, "median_seconds" => 10_800, "resolved" => 1)
      expect(body["subjects"]).to eq([ { "category" => "maquininha", "count" => 2 }, { "category" => "pix", "count" => 1 } ])
      expect(body["brands"]).to eq([ { "brand" => "infinitepay", "count" => 3 } ])
      expect(body["daily"].size).to eq(7)
      expect(body["daily"].first).to eq("date" => "2026-11-16", "received" => 0, "resolved" => 0)
      expect(body["daily"].last).to eq("date" => "2026-11-22", "received" => 3, "resolved" => 1)
    end

    it "responde vazio, sem erro, para quem ainda não atendeu nada" do
      body = get_as("Olivia", "/api/dashboard/analysts/#{ana.id}")

      expect(body).to include("received" => 0, "answered" => 0, "resolved" => 0, "open" => 0, "messages_sent" => 0)
      expect(body["first_reply"]).to eq("mean_seconds" => nil, "answered" => 0)
      expect(body["sla"]).to eq("met" => 0, "missed" => 0, "percent" => nil)
      expect(body["subjects"]).to eq([])
    end

    it "deixa o analista ver colegas das mesmas marcas, mas só com os tickets das marcas dele" do
      duo = create_analyst("Duo", brands: %w[infinitepay jim])
      escalate(ticket_at("d1", now - 2.hours), at: now - 2.hours, agent: duo, category: "pix")
      escalate(ticket_at("d2", now - 2.hours, brand: "jim"), at: now - 2.hours, agent: duo, category: "pix")

      as_ana = get_as("Ana", "/api/dashboard/analysts/#{duo.id}")
      as_ops = get_as("Olivia", "/api/dashboard/analysts/#{duo.id}")

      expect(as_ana["received"]).to eq(1)
      expect(as_ana["brands"]).to eq([ { "brand" => "infinitepay", "count" => 1 } ])
      expect(as_ops["received"]).to eq(2)
      expect(as_ops["brands"].map { |row| row["brand"] }).to contain_exactly("infinitepay", "jim")
    end

    it "responde 404 para analista de outra marca, para quem não é analista e para id desconhecido" do
      jota = create_analyst("Jota", brands: [ "jim" ])
      olivia = User.find_by!(name: "Olivia")

      [ jota.id, olivia.id, SecureRandom.uuid ].each do |id|
        get "/api/dashboard/analysts/#{id}", headers: auth_as("Ana")
        expect(response).to have_http_status(:not_found)
      end
    end

    it "exige login" do
      get "/api/dashboard/analysts/#{ana.id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/dashboard/resolution" do
    def seed_resolutions
      close(ticket_at("ia", now - 3.hours), now - 3.hours + 10.minutes, code: "ai_resolved", category: "pix")
      close(ticket_at("h1", now - 5.hours), now - 3.hours, agent: ana, category: "maquininha")
      close(ticket_at("h2", now - 50.hours, brand: "jim"), now - 20.hours, category: "maquininha")
      close(ticket_at("h3", now - 10.hours), now - 1.hour, agent: ana, category: "pix")
    end

    it "detalha o tempo de solução: média, mediana, meta, faixas, IA contra humano, marcas, assuntos e os mais lentos" do
      seed_resolutions

      body = get_as("Olivia", "/api/dashboard/resolution")

      expect(body).to include("target_seconds" => 28_800, "resolved" => 4, "median_seconds" => 19_800,
                              "mean_seconds" => 37_050, "within_target_percent" => 50)
      expect(body["by_resolver"]).to eq(
        "ai" => { "count" => 1, "median_seconds" => 600, "mean_seconds" => 600 },
        "human" => { "count" => 3, "median_seconds" => 32_400, "mean_seconds" => 49_200 }
      )
      expect(body["buckets"]).to eq([
        { "key" => "up_to_15m", "count" => 1 }, { "key" => "15m_to_1h", "count" => 0 }, { "key" => "1h_to_8h", "count" => 1 },
        { "key" => "8h_to_24h", "count" => 1 }, { "key" => "over_24h", "count" => 1 }
      ])
      expect(body["brands"]).to eq([
        { "brand" => "infinitepay", "resolved" => 3, "median_seconds" => 7200 },
        { "brand" => "jim", "resolved" => 1, "median_seconds" => 108_000 }
      ])
      expect(body["categories"]).to eq([
        { "category" => "maquininha", "resolved" => 2, "median_seconds" => 57_600 },
        { "category" => "pix", "resolved" => 2, "median_seconds" => 16_500 }
      ])
      expect(body["slowest"].map { |row| [ row["brand"], row["seconds"], row["resolved_by"], row["agent"] ] }).to eq([
        [ "jim", 108_000, "human", nil ], [ "infinitepay", 32_400, "human", "Ana" ],
        [ "infinitepay", 7200, "human", "Ana" ], [ "infinitepay", 600, "ai", nil ]
      ])
      expect(body["daily"].last).to eq("date" => "2026-11-22", "resolved" => 3, "median_seconds" => 7200)
      expect(body["daily"][-2]).to eq("date" => "2026-11-21", "resolved" => 1, "median_seconds" => 108_000)
      expect(body["daily"].first).to eq("date" => "2026-11-16", "resolved" => 0, "median_seconds" => nil)
    end

    it "mostra ao analista só as marcas dele" do
      seed_resolutions

      body = get_as("Ana", "/api/dashboard/resolution")

      expect(body["resolved"]).to eq(3)
      expect(body["brands"].map { |row| row["brand"] }).to eq([ "infinitepay" ])
    end

    it "responde vazio, sem erro, quando nada foi resolvido" do
      body = get_as("Ana", "/api/dashboard/resolution")

      expect(body).to include("resolved" => 0, "median_seconds" => nil, "mean_seconds" => nil, "within_target_percent" => nil)
      expect(body["slowest"]).to eq([])
    end
  end

  describe "GET /api/dashboard/team" do
    def seed_team
      resolved = escalate(ticket_at("a1", now - 4.hours), at: now - 3.hours, answered_after: 10.minutes, due: now - 2.hours,
                                                          agent: ana, category: "maquininha")
      close(resolved, now - 1.hour, agent: ana, category: "maquininha")
      analyst_message(resolved, now - 2.hours)
      working = escalate(ticket_at("a2", now - 2.hours), at: now - 90.minutes, answered_after: 30.minutes, due: now - 80.minutes,
                                                         agent: ana, category: "pix")
      analyst_message(working, now - 1.hour)
      escalate(ticket_at("a3", now - 1.hour), at: now - 1.hour, agent: ana, category: "maquininha")
      @bia = create_analyst("Bia")
      escalate(ticket_at("b1", now - 1.hour), at: now - 1.hour, agent: @bia, category: "pix")
    end

    it "mostra o time inteiro: totais, uma linha por analista, assuntos mais tratados e a série diária" do
      seed_team

      body = get_as("Olivia", "/api/dashboard/team")

      expect(body["totals"]).to eq(
        "received" => 4, "answered" => 2, "resolved" => 1, "open" => 3, "messages_sent" => 2,
        "first_reply_mean_seconds" => 1200, "sla_percent" => 50, "solution_mean_seconds" => 10_800
      )
      expect(body["agents"]).to eq([
        { "id" => ana.id, "name" => "Ana", "brands" => [ "infinitepay" ], "received" => 3, "answered" => 2, "resolved" => 1,
          "open" => 2, "first_reply_mean_seconds" => 1200, "sla_percent" => 50, "solution_mean_seconds" => 10_800,
          "top_subject" => "maquininha" },
        { "id" => @bia.id, "name" => "Bia", "brands" => [ "infinitepay" ], "received" => 1, "answered" => 0, "resolved" => 0,
          "open" => 1, "first_reply_mean_seconds" => nil, "sla_percent" => nil, "solution_mean_seconds" => nil,
          "top_subject" => "pix" }
      ])
      expect(body["subjects"]).to eq([ { "category" => "maquininha", "count" => 2 }, { "category" => "pix", "count" => 2 } ])
      expect(body["daily"].size).to eq(7)
      expect(body["daily"].last).to eq("date" => "2026-11-22", "received" => 4, "resolved" => 1)
    end

    it "mostra ao analista só os colegas que atendem uma marca dele, e a operação vê todos" do
      duo = create_analyst("Duo", brands: %w[infinitepay jim])
      jota = create_analyst("Jota", brands: [ "jim" ])
      escalate(ticket_at("d1", now - 2.hours), at: now - 2.hours, agent: duo, category: "pix")
      escalate(ticket_at("d2", now - 2.hours, brand: "jim"), at: now - 2.hours, agent: duo, category: "pix")
      escalate(ticket_at("j1", now - 2.hours, brand: "jim"), at: now - 2.hours, agent: jota, category: "pix")

      as_ana = get_as("Ana", "/api/dashboard/team")
      as_ops = get_as("Olivia", "/api/dashboard/team")

      expect(as_ana["agents"].map { |row| row["name"] }).to contain_exactly("Ana", "Duo")
      expect(as_ana["agents"].find { |row| row["name"] == "Duo" }["received"]).to eq(1)
      expect(as_ops["agents"].map { |row| row["name"] }).to contain_exactly("Ana", "Duo", "Jota")
      expect(as_ops["totals"]["received"]).to eq(3)
    end

    it "responde vazio, sem erro, quando ninguém atendeu nada" do
      body = get_as("Olivia", "/api/dashboard/team")

      expect(body["totals"]).to include("received" => 0, "answered" => 0, "sla_percent" => nil, "first_reply_mean_seconds" => nil)
      expect(body["agents"].map { |row| row["name"] }).to eq([ "Ana" ])
      expect(body["subjects"]).to eq([])
    end

    it "exige login" do
      get "/api/dashboard/team"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/dashboard/tickets" do
    def seed_attention
      waiting = escalate(ticket_at("espera", now - 1.hour), at: now - 30.minutes, due: now - 10.minutes, mode: "pending_human", category: "pix")
      waiting.update_columns(priority: "p1")
      mine = escalate(ticket_at("dela", now - 3.hours), at: now - 2.hours, answered_after: 10.minutes, due: now - 1.hour, agent: ana)
      mine.update_columns(priority: "p3")
      jim = escalate(ticket_at("jim", now - 2.hours, brand: "jim"), at: now - 1.hour, due: now + 30.minutes, mode: "pending_human")
      jim.update_columns(priority: "p2")
      @stale = ticket_at("parado", now - 4.days)
      close(ticket_at("fechado", now - 5.hours), now - 1.hour)
      [ waiting, mine, jim ]
    end

    it "lista os tickets que pedem gente, com o prazo, e conta parados, sem analista e atrasados" do
      waiting, mine, jim = seed_attention

      body = get_as("Olivia", "/api/dashboard/tickets")

      expect(body["counts"]).to eq(
        "attention" => 3, "unassigned" => 2, "overdue" => 1, "stale" => 1,
        "by_priority" => { "p1" => 1, "p2" => 1, "p3" => 1, "p4" => 0 },
        "by_brand" => [ { "brand" => "infinitepay", "count" => 2 }, { "brand" => "jim", "count" => 1 } ]
      )
      expect(body["tickets"].map { |row| row["id"] }).to eq([ waiting.id, jim.id, mine.id ])
      expect(body["tickets"].first).to include(
        "brand" => "infinitepay", "priority" => "p1", "mode" => "pending_human", "agent" => nil, "agent_id" => nil,
        "category" => "pix", "subject" => "minha maquininha não liga", "waiting_seconds" => 1800, "overdue" => true
      )
      expect(body["tickets"].last).to include("agent" => "Ana", "agent_id" => ana.id, "overdue" => false, "mode" => "human")
      expect(body["tickets"][1]).to include("brand" => "jim", "overdue" => false)
    end

    it "lista os tickets parados há mais de 3 dias, de qualquer modo" do
      seed_attention

      stale = get_as("Olivia", "/api/dashboard/tickets")["stale_tickets"]

      expect(stale.map { |row| [ row["id"], row["mode"], row["age_seconds"] ] }).to eq([ [ @stale.id, "ai", 4 * 24 * 3600 ] ])
      expect(stale.first).to include("brand" => "infinitepay", "subject" => "minha maquininha não liga")
    end

    it "mostra ao analista só as marcas dele" do
      seed_attention

      body = get_as("Ana", "/api/dashboard/tickets")

      expect(body["counts"]["attention"]).to eq(2)
      expect(body["counts"]["by_brand"]).to eq([ { "brand" => "infinitepay", "count" => 2 } ])
      expect(body["tickets"].map { |row| row["brand"] }.uniq).to eq([ "infinitepay" ])
    end

    it "responde vazio, sem erro, quando nada pede gente" do
      body = get_as("Ana", "/api/dashboard/tickets")

      expect(body["counts"]).to include("attention" => 0, "unassigned" => 0, "overdue" => 0, "stale" => 0)
      expect(body["tickets"]).to eq([])
      expect(body["stale_tickets"]).to eq([])
    end

    it "exige login" do
      get "/api/dashboard/tickets"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
