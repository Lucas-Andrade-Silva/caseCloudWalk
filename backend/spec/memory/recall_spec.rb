require "rails_helper"

RSpec.describe Memory::Recall do
  let(:noon) { Time.zone.parse("2026-11-15 12:00:00") }

  before do
    create_brand("infinitepay")
    create_brand("jim")
  end

  # Um ticket do cliente cust-42 aberto em `at`, fechado meia hora depois com resumo que expira em `expires_in`.
  def past_ticket(at:, brand: "infinitepay", channel: "whatsapp", customer: "cust-42", expires_in: 90.days)
    travel_to(at)
    ticket = receive_message(provider_message_id: "wamid.#{SecureRandom.hex(4)}", brand_slug: brand,
                             channel: channel, customer_external_id: customer).ticket
    ticket.update!(mode: "closed", closed_at: at + 30.minutes, resolution_code: "resolved")
    ClosingSummary.create!(ticket: ticket, brand: ticket.brand, customer: ticket.customer, version: 1,
                           source: "template", text: "resumo #{ticket.id}", expires_at: at + 30.minutes + expires_in)
    ticket
  end

  def current_ticket
    travel_to(noon)
    receive_message(provider_message_id: "wamid.agora", channel: "app_chat").ticket
  end

  it "traz os 5 tickets mais recentes do cliente na mesma marca, de qualquer canal, sem o próprio" do
    older = Array.new(6) { |i| past_ticket(at: noon - (10 - i).days, channel: Ticket::CHANNELS[i % 3]) }
    past_ticket(at: noon - 1.day, brand: "jim")
    past_ticket(at: noon - 1.day, customer: "outro")
    ticket = current_ticket

    memory = described_class.call(ticket: ticket, now: noon)

    expect(memory[:window_days]).to eq(90)
    expect(memory[:tickets].map { |item| item[:ticket_id] }).to eq(older.last(5).reverse.map(&:id))
    expect(memory[:tickets].first).to include(
      channel: older.last.channel, mode: "closed", resolution_code: "resolved", priority: "p3", queue: nil,
      tags: [], escalation_reason: nil, summary: "resumo #{older.last.id}",
      opened_at: older.last.created_at.iso8601(3), closed_at: older.last.closed_at.iso8601(3)
    )
  end

  it "ignora tickets fora da janela e esconde resumo expirado" do
    past_ticket(at: noon - 91.days)
    expired = past_ticket(at: noon - 20.days, expires_in: 1.day)

    memory = described_class.call(ticket: current_ticket, now: noon)

    expect(memory[:tickets].map { |item| [ item[:ticket_id], item[:summary] ] }).to eq([ [ expired.id, nil ] ])
  end

  it "ignora o que veio antes da exclusão da memória" do
    past_ticket(at: noon - 5.days)
    ticket = current_ticket
    ticket.customer.update!(memory_erased_at: noon - 1.day)

    expect(described_class.call(ticket: ticket, now: noon)[:tickets]).to eq([])
  end
end
