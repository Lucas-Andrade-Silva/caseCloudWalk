require "rails_helper"

RSpec.describe "GET /metrics" do
  let(:noon) { Time.zone.parse("2026-11-18 12:00:00") }

  before do
    create_brand("infinitepay")
    create_brand("jim")
  end

  def metric(body, name, labels = {})
    selector = labels.empty? ? "" : "{#{labels.map { |key, value| %(#{key}="#{value}") }.join(',')}}"
    line = body.lines.find { |candidate| candidate.start_with?("#{name}#{selector} ") }
    line && Float(line.split.last)
  end

  it "expõe as medidas do domínio lidas do banco a cada coleta" do
    travel_to(noon - 2.minutes)
    receive_message(provider_message_id: "w1", customer_external_id: "c1") # na IA, esperando o agente
    travel_to(noon - 10.minutes)
    escalated_ticket("c2") # esperando humano há 10 min
    receive_message(provider_message_id: "w3", brand_slug: "jim", customer_external_id: "c3")
    travel_to(noon)

    get "/metrics"

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with("text/plain; version=0.0.4") # formato de texto do Prometheus
    body = response.body
    expect(metric(body, "helpdesk_outbox_pending_events")).to eq(4.0)
    expect(metric(body, "helpdesk_outbox_oldest_pending_age_seconds")).to eq(600.0)
    expect(metric(body, "helpdesk_outbox_parked_events")).to eq(0.0)
    expect(metric(body, "helpdesk_open_tickets", brand: "infinitepay", mode: "ai")).to eq(1.0)
    expect(metric(body, "helpdesk_open_tickets", brand: "infinitepay", mode: "pending_human")).to eq(1.0)
    expect(metric(body, "helpdesk_open_tickets", brand: "jim", mode: "ai")).to eq(1.0)
    expect(metric(body, "helpdesk_open_tickets", brand: "jim", mode: "human")).to eq(0.0)
    expect(metric(body, "helpdesk_oldest_waiting_human_age_seconds", brand: "infinitepay")).to eq(600.0)
    expect(metric(body, "helpdesk_oldest_waiting_human_age_seconds", brand: "jim")).to eq(0.0)
    expect(metric(body, "helpdesk_tickets_waiting_agent", brand: "infinitepay")).to eq(1.0)
  end

  it "conta as requisições por rota, com os identificadores colapsados" do
    get "/api/tickets/#{SecureRandom.uuid}"
    get "/metrics"

    # O registro é do processo inteiro: outros testes podem ter somado nesta rota antes deste.
    expect(response.body).to match(%r{^http_server_requests_total\{code="401",method="get",path="/api/tickets/:uuid"\} \d+\.0$})
    expect(response.body).not_to include("/api/tickets/#{SecureRandom.uuid[0, 8]}")
  end
end
