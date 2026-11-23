require "rails_helper"

RSpec.describe "Por que a IA decidiu" do
  let(:brand) { Brand.find_by!(slug: "infinitepay") }

  before do
    create_brand
    create_analyst("Ana")
    queue = TicketQueue.create!(brand: brand, team: default_queue.team, slug: "maquininha", name: "Maquininha")
    RuleSet.create!(brand: brand, version: 3, rules: [
      { "id" => "maquininha-llm", "name" => "Maquininha (LLM)",
        "when" => { "fact" => "category", "op" => "eq", "value" => "maquininha" },
        "then" => { "queue" => queue.slug, "priority" => "p1", "tags" => [ "dispositivo" ] } }
    ]).publish!
  end

  def explain(ticket)
    get "/api/tickets/#{ticket.id}/explanation", headers: auth_as("Ana")
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it "conta a cadeia: abertura, regras, fatos da LLM com confiança, regra que casou com versão, escalação e brief" do
    ticket = receive_message(text: "minha maquininha não liga, CPF 529.982.247-25").ticket
    Llm::Enrich.call(ticket, client: Llm::Client.new(mode: "stub"))
    ticket.with_lock { Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: "device_issue", actor: "bot") }
    Llm::Summaries.brief(ticket.reload, client: Llm::Client.new(mode: "off"))

    body = explain(ticket)

    expect(body["redacted_text"]).to eq("minha maquininha não liga, CPF [CPF]")
    expect(body["redactions"]).to eq("cpf" => 1)
    kinds = body["steps"].map { |step| step["kind"] }
    expect(kinds).to eq(%w[opened rule llm_facts rule escalated rule brief_fallback])

    opening = body["steps"][1]
    expect(opening).to include("step" => "routing.opening", "rule" => nil)

    llm = body["steps"][2]
    expect(llm).to include("category" => "maquininha", "confidence" => 0.6, "accepted" => true, "min_confidence" => 0.5,
                           "source" => "stub", "model" => "openai/gpt-oss-120b", "prompt_version" => "enrich-v2")

    enrichment = body["steps"][3]
    expect(enrichment).to include("step" => "routing.enrichment", "rule_set_version" => 3,
                                  "output" => { "queue" => "maquininha", "priority" => "p1", "tags" => [ "dispositivo" ] })
    expect(enrichment["rule"]).to eq("id" => "maquininha-llm", "name" => "Maquininha (LLM)",
                                     "when" => { "fact" => "category", "op" => "eq", "value" => "maquininha" })
    expect(enrichment["facts"]).to include("category" => "maquininha", "channel" => "whatsapp")

    expect(body["steps"][4]).to include("trigger" => "agent_requested", "reason" => "device_issue")
    expect(body["steps"][6]).to include("reason" => "disabled")
    expect(body.to_json).not_to include("529.982.247-25")
    expect(body.to_json).not_to include("message_text")
  end

  it "com a LLM fora ou sem confiança, mostra o fallback para as regras" do
    ticket = receive_message.ticket
    Llm::Enrich.call(ticket, client: Llm::Client.new(mode: "off"))

    steps = explain(ticket)["steps"]

    expect(steps.map { |step| step["kind"] }).to eq(%w[opened rule llm_fallback])
    expect(steps.last).to include("reason" => "disabled")
  end

  it "traz o trace do ticket, quando a plataforma registrou um" do
    ticket = receive_message.ticket
    OutboxEvent.create!(event_id: SecureRandom.uuid, topic: "agent.events", key: ticket.id, payload: { ticket_id: ticket.id },
                        headers: { "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" })

    expect(explain(ticket)["trace_id"]).to eq("4bf92f3577b34da6a3ce929d0e0e4736")
  end

  it "ticket de marca que o analista não atende responde 404" do
    create_brand("jim")
    ticket = receive_message(brand_slug: "jim", provider_message_id: "wamid.j").ticket

    get "/api/tickets/#{ticket.id}/explanation", headers: auth_as("Ana")

    expect(response).to have_http_status(:not_found)
  end
end
