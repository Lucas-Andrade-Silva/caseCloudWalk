require "rails_helper"

RSpec.describe Incidents::Detect do
  before do
    create_brand
    create_brand("jim")
  end

  def open_ticket(index, brand: "infinitepay", category: "maquininha", tags: nil, at: Time.current)
    travel_to(at) do
      ticket = receive_message(provider_message_id: "wamid.#{brand}.#{index}", customer_external_id: "c-#{brand}-#{index}",
                               brand_slug: brand).ticket
      ticket.update!(llm_facts: category ? { "category" => category } : {})
      ticket.update!(tags: tags) if tags
      ticket
    end
  end

  it "abre um incidente com 5 tickets abertos da mesma categoria e marca em 10 minutos, e liga todos" do
    tickets = Array.new(5) { |index| open_ticket(index, at: index.minutes.ago) }

    incident = described_class.call(tickets.last)

    expect(incident).to have_attributes(status: "open", key: "categoria:maquininha", label: "maquininha",
                                        brand: Brand.find_by!(slug: "infinitepay"), title_source: "template")
    expect(incident.title).to eq("Pico de maquininha na Infinitepay")
    expect(incident.draft_reply).to be_present
    expect(tickets.map { |ticket| ticket.reload.incident_id }).to all(eq(incident.id))
    expect(ConversationEvent.where(kind: "ticket.incident_linked").count).to eq(5)
  end

  it "abaixo do limite, fora da janela ou de outra marca, não abre" do
    3.times { |index| open_ticket(index) }
    open_ticket(3, at: 11.minutes.ago)
    open_ticket(4, brand: "jim")

    expect(described_class.call(Ticket.order(:created_at).last)).to be_nil
    expect(Incident.count).to eq(0)
  end

  it "com um incidente aberto, o ticket novo da mesma chave entra nele" do
    5.times { |index| open_ticket(index) }
    incident = described_class.call(Ticket.last)

    newcomer = open_ticket(5)
    expect(described_class.call(newcomer)).to eq(incident)

    expect(newcomer.reload.incident_id).to eq(incident.id)
    expect(Incident.count).to eq(1)
  end

  it "sem categoria útil da LLM, agrupa pela primeira tag; sem nenhuma das duas, não agrupa" do
    tickets = Array.new(5) { |index| open_ticket(index, category: "outro", tags: [ "dispositivo", "p1" ]) }
    loose = open_ticket(9, category: nil)

    expect(described_class.call(tickets.last)).to have_attributes(key: "tag:dispositivo", label: "dispositivo")
    expect(described_class.call(loose)).to be_nil
  end

  it "pedido de falar com humano não vira incidente" do
    tickets = Array.new(6) { |index| open_ticket(index, category: "falar_com_humano") }

    expect(described_class.call(tickets.last)).to be_nil
  end

  it "não conta tickets fechados" do
    tickets = Array.new(5) { |index| open_ticket(index) }
    tickets.first.update_columns(mode: "closed")

    expect(described_class.call(tickets.last)).to be_nil
  end

  it "o mapa vivo recebe o incidente de cada ticket" do
    5.times { |index| open_ticket(index) }
    incident = described_class.call(Ticket.last)

    expect(Live::MapItem.call(Ticket.last.reload)).to include(incident_id: incident.id)
  end
end

RSpec.describe Incidents::Summarize do
  before { create_brand }

  def incident_with_tickets
    tickets = Array.new(5) do |index|
      ticket = receive_message(provider_message_id: "wamid.#{index}", customer_external_id: "c-#{index}",
                               text: "minha maquininha não liga, CPF 529.982.247-25").ticket
      ticket.update!(llm_facts: { "category" => "maquininha" })
      ticket
    end
    Incidents::Detect.call(tickets.last)
  end

  it "a LLM escreve título e rascunho, com origem e versão do prompt" do
    incident = incident_with_tickets

    described_class.call(incident, client: Llm::Client.new(mode: "stub"))

    expect(incident.reload).to have_attributes(title_source: "stub", prompt_version: "incident-v1")
    expect(incident.title).to start_with("Teste:")
    expect(incident.draft_reply).not_to include("529.982.247-25")
  end

  it "com o LLM fora, mantém o título e o rascunho do template" do
    incident = incident_with_tickets
    template_title = incident.title

    described_class.call(incident, client: Llm::Client.new(mode: "off"))

    expect(incident.reload).to have_attributes(title: template_title, title_source: "template")
  end
end

RSpec.describe DetectIncidentJob do
  before { create_brand }

  it "a entrada pede a detecção depois do commit, para todo ticket aberto" do
    ticket = receive_message.ticket
    receive_message(provider_message_id: "wamid.2", text: "alguém aí?")

    expect(described_class.jobs.map { |job| job["args"] }).to eq([ [ ticket.id ] ])
  end

  it "o enriquecimento pede de novo, porque a categoria pode ter mudado a chave" do
    ticket = receive_message.ticket
    described_class.jobs.clear

    Llm::Enrich.call(ticket, client: Llm::Client.new(mode: "stub"))

    expect(described_class.jobs.map { |job| job["args"] }).to eq([ [ ticket.id ] ])
  end
end
