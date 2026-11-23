require "rails_helper"

RSpec.describe Demo::Reset do
  before do
    create_brand
    create_brand("jim")
    create_analyst("Ana")
  end

  it "apaga as conversas e mantém marcas, equipes, filas, regras e pessoas" do
    rule_set = RuleSet.create!(brand: Brand.find_by!(slug: "infinitepay"), version: 1, rules: [])
    tickets = Array.new(5) do |index|
      receive_message(provider_message_id: "wamid.#{index}", customer_external_id: "c-#{index}").ticket
    end
    tickets.each { |ticket| ticket.update!(llm_facts: { "category" => "maquininha" }) }
    Incidents::Detect.call(tickets.last)
    escalated_ticket("c-escalado")

    described_class.call

    [ Ticket, Message, ConversationEvent, Decision, Incident, Customer, InboundEvent, OutboxEvent, ClosingSummary ]
      .each { |model| expect(model.count).to eq(0), "#{model} ficou com #{model.count}" }
    expect(Brand.count).to eq(2)
    expect(TicketQueue.count).to eq(2)
    expect(User.find_by(name: "Ana")).to be_present
    expect(RuleSet.find(rule_set.id)).to be_present
  end

  it "junta as equipes duplicadas dos seeds antigos na equipe dona da fila padrão" do
    ana = User.find_by!(name: "Ana")
    legacy = Team.create!(slug: "atendimento-infinitepay", name: "Atendimento InfinitePay")
    TeamMembership.create!(user: ana, team: legacy)
    bruno = create_analyst("Bruno", brands: [])
    TeamMembership.create!(user: bruno, team: legacy)

    described_class.call

    expect(Team.find_by(slug: "atendimento-infinitepay")).to be_nil
    owner = default_queue.team
    expect(owner.team_memberships.map { |membership| membership.user.name }).to contain_exactly("Ana", "Bruno")
  end

  it "com histórico, deixa uma cliente com atendimentos anteriores para a demo da memória" do
    described_class.call(history: true)

    customer = Customer.find_by!(external_id: Demo::Reset::HISTORY_CUSTOMER)
    expect(customer.tickets.where(mode: "closed").count).to eq(2)

    ticket = receive_message(provider_message_id: "wamid.demo", customer_external_id: Demo::Reset::HISTORY_CUSTOMER,
                             text: "a maquininha travou de novo").ticket
    memory = Memory::Recall.call(ticket: ticket)
    expect(memory[:tickets].size).to eq(2)
    expect(memory[:tickets].map { |item| item[:summary] }).to all(be_present)
  end
end
