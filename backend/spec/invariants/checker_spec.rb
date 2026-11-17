require "rails_helper"

RSpec.describe Invariants::Checker do
  let(:now) { Time.zone.parse("2026-11-16 12:00:00") }

  before do
    create_brand
    create_bot
    travel_to(now - 5.minutes)
  end

  def entry(id, channel: "whatsapp") = { "channel" => channel, "provider_message_id" => id }

  def message_from(customer, id, text: "oi")
    receive_message(provider_message_id: id, customer_external_id: customer, text: text)
  end

  def answer(result, to_seq: result.message.seq)
    Agent::RecordReply.call(agent_turn_id: SecureRandom.uuid, ticket_id: result.ticket.id, in_reply_to_seq: to_seq,
                            handoff_epoch: result.ticket.reload.handoff_epoch, action: "reply", text: "resposta")
  end

  def check(ledger)
    travel_to(now)
    described_class.call(ledger: ledger, orphan_after: 60)
  end

  it "passa quando toda mensagem foi respondida ou escalada, contando reentregas uma vez só" do
    answered = message_from("c-1", "m-1")
    answer(answered)
    escalated = message_from("c-2", "m-2")
    escalated.ticket.with_lock do
      Handoff::Escalate.call(ticket: escalated.ticket, trigger: "agent_requested", reason: "x", actor: "bot")
    end

    report = check([ entry("m-1"), entry("m-2"), entry("m-1") ])

    expect(report).to include(ok: true, ledger_entries: 3, unique_messages: 2, ingested: 2, answered: 1, escalated: 1)
    expect(report[:violations].values).to all(be_empty)
  end

  it "só cobra as mensagens que a plataforma confirmou com 2xx" do
    answer(message_from("c-1", "m-1"))

    report = check([ entry("m-1").merge("status" => 201), entry("recusada").merge("status" => 503),
                     entry("sem-resposta").merge("status" => "Net::ReadTimeout") ])

    expect(report).to include(ok: true, unique_messages: 1, not_acknowledged: 2)
  end

  it "acusa a mensagem que nunca entrou e a que ficou sem resposta com a IA" do
    message_from("c-1", "m-1")

    report = check([ entry("m-1"), entry("nunca-chegou") ])

    expect(report[:ok]).to be(false)
    expect(report[:violations][:lost]).to contain_exactly(
      include(provider_message_id: "nunca-chegou", reason: "not_ingested"),
      include(provider_message_id: "m-1", reason: "unanswered")
    )
  end

  it "acusa duas respostas do bot para a mesma mensagem" do
    result = message_from("c-1", "m-1")
    2.times do
      result.ticket.append_message!(sender: "bot", body: "oi", in_reply_to_seq: 1, agent_turn_id: SecureRandom.uuid)
    end

    report = check([ entry("m-1") ])

    expect(report[:violations][:duplicates]).to eq([ { ticket_id: result.ticket.id, in_reply_to_seq: 1, count: 2 } ])
  end

  it "acusa buraco no seq e horário fora de ordem" do
    result = message_from("c-1", "m-1")
    answer(result)
    Message.create!(ticket: result.ticket, brand_id: result.ticket.brand_id, seq: 5, sender: "customer", body: "x")
    other = message_from("c-2", "m-2")
    answer(other)
    other.ticket.messages.find_by!(seq: 2).update_columns(created_at: now - 1.hour)

    report = check([ entry("m-1"), entry("m-2") ])

    expect(report[:violations][:order]).to contain_exactly(
      include(ticket_id: result.ticket.id, reason: "seq_gap"),
      include(ticket_id: other.ticket.id, reason: "time_goes_back")
    )
  end

  it "acusa ticket esquecido com a IA e ticket escalado sem fila" do
    waiting = message_from("c-1", "m-1")
    waiting.ticket.reload.update_columns(awaiting_agent_since: now - 61.seconds)
    lost_queue = message_from("c-2", "m-2")
    answer(lost_queue)
    lost_queue.ticket.reload.update_columns(mode: "pending_human", queue_id: nil)

    report = check([ entry("m-1"), entry("m-2") ])

    expect(report[:violations][:orphans]).to contain_exactly(
      include(ticket_id: waiting.ticket.id, reason: "agent_silence_not_escalated"),
      include(ticket_id: lost_queue.ticket.id, reason: "escalated_without_queue")
    )
  end
end
