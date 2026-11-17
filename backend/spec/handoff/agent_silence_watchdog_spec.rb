require "rails_helper"

RSpec.describe Handoff::AgentSilenceWatchdog do
  let(:t0) { Time.zone.parse("2026-11-15 12:00:00") }
  let(:watchdog) { described_class.new(timeout: 30) }

  before do
    create_brand
    create_bot
  end

  def bot_reply(ticket, to_seq)
    Agent::RecordReply.call(agent_turn_id: SecureRandom.uuid, ticket_id: ticket.id, in_reply_to_seq: to_seq,
                            handoff_epoch: 0, action: "reply", text: "resposta")
  end

  it "escala o ticket cujo cliente espera o agente há mais de 30 s" do
    travel_to(t0)
    ticket = receive_message.ticket

    travel_to(t0 + 29)
    expect(watchdog.run).to eq(0)
    expect(ticket.reload.mode).to eq("ai")

    travel_to(t0 + 31)
    expect(watchdog.run).to eq(1)
    expect(ticket.reload).to have_attributes(mode: "pending_human", escalation_trigger: "agent_timeout",
                                             escalation_reason: "agent_silence")
    event = ticket.conversation_events.order(:id).last
    expect(event).to have_attributes(kind: "ticket.escalated", actor: "system")
    expect(event.data).to include("waited_seconds" => 31)
  end

  it "não escala duas vezes o mesmo ticket" do
    travel_to(t0)
    receive_message
    travel_to(t0 + 31)

    2.times { watchdog.run }

    expect(ConversationEvent.where(kind: "ticket.escalated").count).to eq(1)
  end

  it "deixa em paz o ticket que o agente já respondeu" do
    travel_to(t0)
    ticket = receive_message.ticket
    travel_to(t0 + 5)
    bot_reply(ticket, 1)

    travel_to(t0 + 60)

    expect(watchdog.run).to eq(0)
  end

  it "conta a espera a partir da mensagem do cliente que ainda não teve resposta" do
    travel_to(t0)
    ticket = receive_message.ticket
    travel_to(t0 + 20)
    receive_message(provider_message_id: "wamid.2", text: "alguém?")
    travel_to(t0 + 25)
    bot_reply(ticket, 1) # resposta atrasada: a mensagem 2 continua sem resposta

    travel_to(t0 + 40)
    expect(watchdog.run).to eq(0)

    travel_to(t0 + 51)
    expect(watchdog.run).to eq(1)
  end

  it "ignora tickets que já não estão com a IA" do
    travel_to(t0)
    ticket = receive_message.ticket
    ticket.update!(mode: "human")

    travel_to(t0 + 60)

    expect(watchdog.run).to eq(0)
  end
end
