require "rails_helper"

RSpec.describe Llm::Enrich do
  let(:brand) { Brand.find_by!(slug: "infinitepay") }
  let(:stub_client) { Llm::Client.new(mode: "stub") }

  before do
    create_brand
    queue = TicketQueue.create!(brand: brand, team: default_queue.team, slug: "maquininha", name: "Maquininha")
    RuleSet.create!(brand: brand, version: 1, rules: [
      { "id" => "maquininha-llm", "name" => "Maquininha (LLM)",
        "when" => { "fact" => "category", "op" => "eq", "value" => "maquininha" },
        "then" => { "queue" => queue.slug, "priority" => "p1", "tags" => [ "dispositivo" ] } }
    ]).publish!
  end

  def fake_client(data)
    result = Llm::Client::Result.new(ok: true, data: data, source: "replay", error: nil,
                                     prompt_version: "enrich-v1", model: "openai/gpt-oss-120b", key: "k")
    Struct.new(:result) { def call(**) = result }.new(result)
  end

  it "grava os fatos com origem, modelo e versão, e as regras reavaliam o ticket com eles" do
    ticket = receive_message(text: "minha maquininha não liga, CPF 529.982.247-25").ticket
    expect(ticket.reload.priority).to eq("p3")

    described_class.call(ticket, client: stub_client)

    ticket.reload
    expect(ticket.llm_facts).to include("category" => "maquininha", "language" => "pt", "frustration" => "baixa",
                                        "confidence" => 0.6, "source" => "stub", "prompt_version" => "enrich-v1",
                                        "model" => "openai/gpt-oss-120b")
    expect(ticket).to have_attributes(priority: "p1", tags: [ "dispositivo" ])
    expect(ticket.queue.slug).to eq("maquininha")
    decision = Decision.where(step: "routing.enrichment").sole
    expect(decision.facts).to include("category" => "maquininha")
    expect(decision.facts.to_json).not_to include("529.982.247-25")
    event = ticket.conversation_events.where(kind: "ticket.enriched").sole
    expect(event.data).to include("category" => "maquininha", "source" => "stub")
    expect(event.data.to_json).not_to include("maquininha não liga")
  end

  it "com o LLM fora, segue só com as regras e registra o motivo" do
    ticket = receive_message.ticket

    described_class.call(ticket, client: Llm::Client.new(mode: "off"))

    ticket.reload
    expect(ticket.llm_facts).to eq({})
    expect(ticket.priority).to eq("p3")
    expect(Decision.where(step: "routing.enrichment")).to be_empty
    expect(ticket.conversation_events.where(kind: "enrichment.skipped").sole.data).to eq("reason" => "disabled")
  end

  it "não usa a categoria quando a confiança fica abaixo do mínimo" do
    ticket = receive_message.ticket

    described_class.call(ticket, client: fake_client("category" => "maquininha", "language" => "pt",
                                                       "frustration" => "baixa", "confidence" => 0.3))

    ticket.reload
    expect(ticket.llm_facts).to include("category" => nil, "confidence" => 0.3)
    expect(ticket.priority).to eq("p3")
  end

  it "não reroteia ticket que já saiu da IA" do
    ticket = escalated_ticket("c-1")
    queue_before = ticket.queue

    described_class.call(ticket, client: stub_client)

    expect(ticket.reload.llm_facts["category"]).to eq("maquininha")
    expect(ticket.queue).to eq(queue_before)
    expect(Decision.where(step: "routing.enrichment")).to be_empty
  end
end

RSpec.describe EnrichTicketJob do
  before { create_brand }

  it "a entrada enfileira o enriquecimento só quando o ticket abre" do
    ticket = receive_message.ticket
    receive_message(provider_message_id: "wamid.2", text: "alguém aí?")

    expect(described_class.jobs.map { |job| job["args"] }).to eq([ [ ticket.id ] ])
  end

  it "com o LLM desligado, nem enfileira" do
    ENV["LLM_MODE"] = "off"
    receive_message
    expect(described_class.jobs).to be_empty
  ensure
    ENV.delete("LLM_MODE")
  end
end
