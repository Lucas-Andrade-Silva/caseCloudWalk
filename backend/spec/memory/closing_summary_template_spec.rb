require "rails_helper"

RSpec.describe Memory::ClosingSummaryTemplate do
  let(:noon) { Time.zone.parse("2026-11-15 12:00:00") }

  before do
    create_brand
    travel_to(noon)
  end

  def closed(ticket, code:, note: nil, at: noon + 30.minutes)
    ticket.update!(mode: "closed", closed_at: at, resolution_code: code, resolution_note: note)
    ticket
  end

  it "resume um ticket que passou por humano, citando a origem, o pedido inicial e a resolução" do
    ticket = escalated_ticket("c-1", priority: "p2")
    ticket.append_message!(sender: "customer", body: "e agora?")
    closed(ticket, code: "resolved", note: "Troquei a bateria.")

    text = described_class.build(ticket.reload)

    expect(text).to eq(
      "Ticket #{ticket.id} via whatsapp, aberto em 15/11/2026 12:00 UTC e fechado em 15/11/2026 12:30 UTC. " \
      "Passou para humano: Escalado pelo agente (motivo: teste), fila infinitepay-atendimento, prioridade p2. " \
      "Pedido inicial: \"minha maquininha não liga\". Resolução: resolvido. Nota: \"Troquei a bateria.\""
    )
  end

  it "diz quando o ticket ficou só com a IA e quando não há nota" do
    ticket = closed(receive_message.ticket, code: "duplicate")

    expect(described_class.build(ticket.reload)).to eq(
      "Ticket #{ticket.id} via whatsapp, aberto em 15/11/2026 12:00 UTC e fechado em 15/11/2026 12:30 UTC. " \
      "Atendido só pela IA. Pedido inicial: \"minha maquininha não liga\". Resolução: duplicado."
    )
  end
end
