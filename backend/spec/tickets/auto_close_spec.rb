require "rails_helper"

RSpec.describe Tickets::AutoClose do
  before { create_brand }

  # Ticket que a IA respondeu: o cliente não espera ninguém.
  def answered_ticket(customer, at:)
    travel_to(at) do
      ticket = receive_message(provider_message_id: "wamid.#{customer}", customer_external_id: customer).ticket
      ticket.agent_answered_through!(ticket.last_customer_seq)
      ticket
    end
  end

  it "fecha o ticket da IA sem mensagem do cliente há 30 minutos, com resolução própria e resumo de memória" do
    ticket = answered_ticket("c-1", at: 31.minutes.ago)

    expect(described_class.new(idle: 30.minutes).run).to eq(1)

    ticket.reload
    expect(ticket).to have_attributes(mode: "closed", resolution_code: "ai_resolved", assignee_id: nil)
    expect(ticket.closed_at).to be_within(5.seconds).of(Time.current)
    expect(ticket.conversation_events.where(kind: "ticket.closed").sole)
      .to have_attributes(actor: "system", data: include("resolution_code" => "ai_resolved", "idle_minutes" => 30))
    expect(ticket.closing_summary.text).to include("Atendido só pela IA.", "Resolução: resolvido pela IA.")
  end

  it "não fecha conversa recente, cliente esperando o agente nem ticket fora da IA" do
    recent = answered_ticket("c-recente", at: 10.minutes.ago)
    waiting = travel_to(40.minutes.ago) { receive_message(provider_message_id: "wamid.w", customer_external_id: "c-espera").ticket }
    human = travel_to(40.minutes.ago) { escalated_ticket("c-humano") }
    old = answered_ticket("c-velho", at: 40.minutes.ago)
    travel_to(5.minutes.ago) { receive_message(provider_message_id: "wamid.velho.2", customer_external_id: "c-velho", text: "e aí?") }

    expect(described_class.new(idle: 30.minutes).run).to eq(0)

    expect([ recent, waiting, human, old ].map { |ticket| ticket.reload.mode }).to eq(%w[ai ai pending_human ai])
  end

  it "se o cliente volta depois, abre um ticket novo e a memória lembra do anterior" do
    first = answered_ticket("c-1", at: 31.minutes.ago)
    described_class.new(idle: 30.minutes).run

    second = receive_message(provider_message_id: "wamid.volta", customer_external_id: "c-1", text: "voltou a falhar").ticket

    expect(second.id).not_to eq(first.id)
    expect(Memory::Recall.call(ticket: second)[:tickets].map { |item| item[:ticket_id] }).to eq([ first.id ])
  end

  it "roda a cada minuto pelo sidekiq-cron" do
    schedule = YAML.safe_load_file(Rails.root.join("config/schedule.yml"))

    expect(schedule.fetch("ai_ticket_auto_close")).to include("class" => "AutoCloseAiTicketsJob", "cron" => "0 * * * * *")
  end
end
