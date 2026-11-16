require "rails_helper"

RSpec.describe "Roteamento por regras" do
  before { create_brand }

  let(:t0) { Time.zone.parse("2026-11-15 12:00:00") }
  let(:brand) { Brand.find_by!(slug: "infinitepay") }
  let!(:credit_queue) do
    TicketQueue.create!(brand: brand, team: default_queue.team, slug: "credito-infinitepay", name: "Crédito")
  end
  let!(:refund_queue) do
    TicketQueue.create!(brand: brand, team: default_queue.team, slug: "estorno-infinitepay", name: "Estorno")
  end

  def publish(rules)
    RuleSet.create!(brand: brand, version: (RuleSet.where(brand: brand).maximum(:version) || 0) + 1, rules: rules)
           .tap(&:publish!)
  end

  let(:credit_rule) do
    { "id" => "credito-alto", "name" => "Crédito alto",
      "when" => { "all" => [ { "fact" => "message_text", "op" => "contains_any", "value" => [ "crédito" ] },
                             { "fact" => "amount", "op" => "gte", "value" => 5000 } ] },
      "then" => { "queue" => "credito-infinitepay", "priority" => "p1", "tags" => [ "alto_valor" ] } }
  end
  let(:refund_on_escalation) do
    { "id" => "estorno-na-escalacao", "name" => "Estorno",
      "when" => { "all" => [ { "fact" => "stage", "op" => "eq", "value" => "escalation" },
                             { "fact" => "escalation_reason", "op" => "eq", "value" => "pedido_de_estorno" } ] },
      "then" => { "queue" => "estorno-infinitepay", "priority" => "p2" } }
  end

  def escalate(ticket, reason)
    ticket.with_lock do
      Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: reason, actor: "bot")
    end
    ticket.reload
  end

  describe "na abertura" do
    it "aplica prioridade, tags e fila prevista da regra publicada e registra a decisão" do
      rule_set = publish([ credit_rule ])

      ticket = receive_message(text: "meu crédito de R$ 8.000,00 sumiu").ticket

      expect(ticket.reload).to have_attributes(priority: "p1", tags: [ "alto_valor" ], queue: credit_queue, mode: "ai")
      decision = Decision.sole
      expect(decision).to have_attributes(
        ticket_id: ticket.id, step: "routing.opening", actor: "rule", rule_set_id: rule_set.id,
        rule_set_version: rule_set.version, matched_rule_id: "credito-alto"
      )
      expect(decision.output).to eq("queue" => "credito-infinitepay", "priority" => "p1", "tags" => [ "alto_valor" ])
      expect(decision.facts).not_to have_key("message_text")
      expect(decision.facts["message_text_sha256"]).to eq(Digest::SHA256.hexdigest("meu crédito de R$ 8.000,00 sumiu"))
    end

    it "usa os padrões e registra a decisão sem regra quando nada está publicado" do
      ticket = receive_message.ticket

      expect(ticket.reload).to have_attributes(priority: "p3", tags: [], queue: nil)
      expect(Decision.sole).to have_attributes(rule_set_id: nil, matched_rule_id: nil, step: "routing.opening")
    end

    it "só roteia na primeira mensagem do ticket" do
      publish([ credit_rule ])
      receive_message(text: "oi")

      receive_message(provider_message_id: "wamid.2", text: "meu crédito de R$ 8.000,00 sumiu")

      expect(Ticket.sole.priority).to eq("p3")
      expect(Decision.count).to eq(1)
    end
  end

  describe "na escalação" do
    it "usa a fila da regra de escalação e o prazo da prioridade final" do
      publish([ refund_on_escalation ])
      travel_to(t0)
      ticket = receive_message.ticket

      escalate(ticket, "pedido_de_estorno")

      expect(ticket).to have_attributes(queue: refund_queue, priority: "p2",
                                        first_response_due_at: t0 + 15.minutes)
      expect(Decision.order(:id).last).to have_attributes(step: "routing.escalation",
                                                          matched_rule_id: "estorno-na-escalacao")
    end

    it "fica com a fila prevista na abertura quando nenhuma regra bate na escalação" do
      opening_only = credit_rule.merge(
        "when" => { "all" => [ { "fact" => "stage", "op" => "eq", "value" => "opening" }, credit_rule["when"] ] }
      )
      publish([ opening_only, refund_on_escalation ])
      ticket = receive_message(text: "meu crédito de R$ 8.000,00 sumiu").ticket

      escalate(ticket, "outro_motivo")

      expect(Decision.order(:id).last).to have_attributes(step: "routing.escalation", matched_rule_id: nil)
      expect(ticket).to have_attributes(queue: credit_queue, priority: "p1")
    end

    it "cai na fila padrão da marca quando não há fila prevista nem regra" do
      ticket = receive_message.ticket

      expect(escalate(ticket, "qualquer").queue).to eq(default_queue)
    end
  end
end
