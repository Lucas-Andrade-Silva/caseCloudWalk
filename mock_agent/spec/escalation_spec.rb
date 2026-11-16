require "spec_helper"

RSpec.describe MockAgent::Responder, "escalação" do
  let(:event) do
    {
      "type" => "message.created", "ticket_id" => "0193a7c2-0000-7000-8000-000000000001",
      "brand" => "jim", "channel" => "app_chat", "mode" => "ai", "handoff_epoch" => 0,
      "message" => { "id" => "m-1", "seq" => 3, "sender" => "customer", "text" => "preciso de um estorno" }
    }
  end

  def event_ids(count) = Array.new(count) { |n| format("0193a7c2-0000-7000-8000-%012d", n) }

  def decision(rate, event_id, text: nil)
    message = text ? event["message"].merge("text" => text) : event["message"]
    described_class.new(escalation_rate: rate).reply_for(event.merge("message" => message), event_id: event_id)
  end

  it "com taxa 0 sempre responde, e com taxa 1 sempre escala" do
    expect(event_ids(50).map { |id| decision(0.0, id)["action"] }).to all(eq("reply"))
    expect(event_ids(50).map { |id| decision(1.0, id)["action"] }).to all(eq("escalate"))
  end

  it "escala com motivo válido, despedida e os mesmos ticket, seq e epoch" do
    escalation = decision(1.0, event_ids(1).first)

    expect(escalation).to include("ticket_id" => event["ticket_id"], "in_reply_to_seq" => 3, "handoff_epoch" => 0)
    expect(escalation["reason"]).to match(/\A[a-z0-9_]{1,64}\z/)
    expect(escalation["text"]).to match(/especialista/i)
  end

  it "decide sempre igual para a mesma mensagem" do
    decisions = event_ids(40).map { |id| decision(0.5, id)["action"] }

    expect(event_ids(40).map { |id| decision(0.5, id)["action"] }).to eq(decisions)
  end

  it "escala perto da fração configurada" do
    escalated = event_ids(2000).count { |id| decision(0.3, id)["action"] == "escalate" }

    expect(escalated / 2000.0).to be_within(0.04).of(0.3)
  end

  it "obedece às marcas [escalar] e [responder] no texto, para demos e cenários" do
    id = event_ids(1).first

    expect(decision(0.0, id, text: "quero um humano [escalar]")["action"]).to eq("escalate")
    expect(decision(1.0, id, text: "só uma dúvida [responder]")["action"]).to eq("reply")
  end

  it "recusa taxa fora de 0 a 1" do
    expect { described_class.new(escalation_rate: 1.5) }.to raise_error(ArgumentError)
    expect { described_class.new(escalation_rate: -0.1) }.to raise_error(ArgumentError)
  end
end
