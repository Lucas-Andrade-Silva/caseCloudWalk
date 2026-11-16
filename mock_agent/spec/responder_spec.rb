require "spec_helper"

RSpec.describe MockAgent::Responder do
  subject(:responder) { described_class.new }

  let(:event) do
    {
      "type" => "message.created",
      "ticket_id" => "0193a7c2-0000-7000-8000-000000000001",
      "brand" => "infinitepay",
      "channel" => "whatsapp",
      "mode" => "ai",
      "handoff_epoch" => 2,
      "customer" => { "id" => "c-1", "external_id" => "cust-42" },
      "message" => { "id" => "m-1", "seq" => 5, "sender" => "customer", "text" => "minha maquininha não liga" }
    }
  end
  let(:event_id) { "0193a7c2-1111-7000-8000-00000000abcd" }

  it "responde à mensagem do cliente apontando ticket, seq e epoch recebidos" do
    reply = responder.reply_for(event, event_id: event_id)

    expect(reply).to include(
      "ticket_id" => "0193a7c2-0000-7000-8000-000000000001",
      "in_reply_to_seq" => 5,
      "handoff_epoch" => 2,
      "action" => "reply"
    )
    expect(reply["text"]).to be_a(String).and(satisfy { |text| !text.strip.empty? })
  end

  it "se identifica como assistente virtual" do
    expect(responder.reply_for(event, event_id: event_id)["text"]).to match(/assistente virtual/i)
  end

  it "é determinístico: a mesma mensagem gera sempre a mesma resposta" do
    first = responder.reply_for(event, event_id: event_id)
    second = described_class.new.reply_for(event, event_id: event_id)

    expect(second).to eq(first)
  end

  it "deriva o agent_turn_id do event_id, para a reentrega não virar uma resposta nova" do
    same = responder.reply_for(event, event_id: event_id)["agent_turn_id"]
    again = responder.reply_for(event, event_id: event_id)["agent_turn_id"]
    other = responder.reply_for(event, event_id: "0193a7c2-2222-7000-8000-00000000abcd")["agent_turn_id"]

    expect(same).to match(/\A\h{8}-\h{4}-5\h{3}-[89ab]\h{3}-\h{12}\z/)
    expect(again).to eq(same)
    expect(other).not_to eq(same)
  end

  it "ignora o que não é mensagem de cliente em ticket no modo ai" do
    expect(responder.reply_for(event.merge("type" => "ticket.closed"), event_id: event_id)).to be_nil
    expect(responder.reply_for(event.merge("mode" => "human"), event_id: event_id)).to be_nil
    expect(responder.reply_for(event.merge("message" => event["message"].merge("sender" => "bot")),
                               event_id: event_id)).to be_nil
  end

  it "ignora evento malformado ou sem event_id, sem levantar erro" do
    expect(responder.reply_for({}, event_id: event_id)).to be_nil
    expect(responder.reply_for("texto solto", event_id: event_id)).to be_nil
    expect(responder.reply_for(event.merge("message" => nil), event_id: event_id)).to be_nil
    expect(responder.reply_for(event, event_id: nil)).to be_nil
  end
end
