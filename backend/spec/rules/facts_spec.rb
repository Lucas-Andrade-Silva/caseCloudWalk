require "rails_helper"

RSpec.describe Rules::Facts do
  let(:t0) { Time.zone.parse("2026-11-15 12:00:00") }

  before { create_brand }

  describe ".amount_in" do
    it "acha o maior valor em dinheiro citado no texto" do
      expect(described_class.amount_in("cobraram R$ 5.000,00 a mais")).to eq(5000.0)
      expect(described_class.amount_in("paguei R$5000 e depois R$ 120,50")).to eq(5000.0)
      expect(described_class.amount_in("charged US$ 1,200.50 twice")).to eq(1200.5)
      expect(described_class.amount_in("refund of $300 please")).to eq(300.0)
      expect(described_class.amount_in("minha maquininha não liga")).to be_nil
    end
  end

  describe ".for_opening" do
    it "monta os fatos da primeira mensagem" do
      travel_to(t0)
      ticket = receive_message(text: "quero estorno de R$ 2.500,00").ticket

      facts = described_class.for_opening(ticket)

      expect(facts).to eq(
        "brand" => "infinitepay", "channel" => "whatsapp", "stage" => "opening",
        "message_text" => "quero estorno de R$ 2.500,00", "customer_recurring" => false,
        "contacts_24h" => 1, "amount" => 2500.0
      )
    end

    it "conta recorrência e contatos em 24 h só até o momento do ticket" do
      travel_to(t0 - 2.days)
      receive_message(provider_message_id: "antigo").ticket.update!(mode: "closed")
      travel_to(t0 - 1.hour)
      receive_message(provider_message_id: "recente", channel: "email")
      travel_to(t0)
      current = receive_message(provider_message_id: "atual", channel: "app_chat").ticket
      travel_to(t0 + 1.hour)
      receive_message(provider_message_id: "depois", channel: "whatsapp")

      facts = described_class.for_opening(current)

      expect(facts).to include("customer_recurring" => true, "contacts_24h" => 2)
    end
  end

  describe ".for_escalation" do
    it "acrescenta os fatos de escalação e junta o texto do cliente" do
      travel_to(t0)
      ticket = receive_message(text: "não recebi meu repasse").ticket
      receive_message(provider_message_id: "wamid.2", text: "eram R$ 900")
      travel_to(t0 + 3.minutes)

      facts = described_class.for_escalation(ticket.reload, trigger: "agent_requested", reason: "precisa_estorno")

      expect(facts).to include(
        "stage" => "escalation", "escalation_trigger" => "agent_requested",
        "escalation_reason" => "precisa_estorno", "ai_minutes" => 3.0, "amount" => 900.0,
        "message_text" => "não recebi meu repasse\neram R$ 900"
      )
    end
  end
end
