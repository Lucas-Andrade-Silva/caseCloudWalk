require "rails_helper"

RSpec.describe Handoff::Escalate do
  let(:opened_at) { Time.zone.parse("2026-11-15 12:00:00") }

  before { create_brand }

  def escalate(ticket, trigger: "agent_requested", reason: "precisa_estorno", actor: "bot", data: {})
    ticket.with_lock do
      described_class.call(ticket: ticket, trigger: trigger, reason: reason, actor: actor, data: data)
    end
    ticket.reload
  end

  it "passa o ticket para a fila humana da marca, com prioridade, prazo, linha do tempo e aviso ao agente" do
    travel_to(opened_at)
    ticket = receive_message.ticket
    travel_to(opened_at + 90)
    receive_message(provider_message_id: "wamid.2", text: "quero falar com alguém")
    travel_to(opened_at + 120)

    escalate(ticket.reload, data: { agent_turn_id: "turno-1" })

    expect(ticket).to have_attributes(
      mode: "pending_human", handoff_epoch: 1, queue: default_queue, priority: "p3", assignee: nil,
      escalated_at: opened_at + 120, first_response_due_at: opened_at + 120 + 1.hour,
      escalation_trigger: "agent_requested", escalation_reason: "precisa_estorno", awaiting_agent_since: nil
    )

    event = ticket.conversation_events.order(:id).last
    expect(event).to have_attributes(kind: "ticket.escalated", actor: "bot")
    expect(event.data).to include(
      "trigger" => "agent_requested", "reason" => "precisa_estorno", "queue_id" => default_queue.id,
      "priority" => "p3", "handoff_epoch" => 1, "agent_turn_id" => "turno-1"
    )

    notice = OutboxEvent.order(:id).last
    expect(notice).to have_attributes(topic: "helpdesk.messages", key: ticket.id)
    expect(notice.payload).to include(
      "type" => "ticket.escalated", "ticket_id" => ticket.id, "mode" => "pending_human",
      "handoff_epoch" => 1, "reason" => "precisa_estorno"
    )
  end

  it "monta o brief do handoff a partir do ticket" do
    travel_to(opened_at)
    ticket = receive_message.ticket
    travel_to(opened_at + 90)
    receive_message(provider_message_id: "wamid.2", text: "quero falar com alguém")
    travel_to(opened_at + 120)

    brief = escalate(ticket.reload).handoff_brief

    expect(brief).to include(
      "source" => "template", "trigger" => "agent_requested", "reason" => "precisa_estorno",
      "brand" => "infinitepay", "channel" => "whatsapp",
      "customer" => { "external_id" => "cust-42", "name" => "Maria" },
      "ai_duration_seconds" => 120, "message_count" => 2,
      "last_customer_message" => "quero falar com alguém"
    )
    expect(brief["recent_messages"].map { |m| [ m["seq"], m["sender"], m["text"] ] }).to eq(
      [ [ 1, "customer", "minha maquininha não liga" ], [ 2, "customer", "quero falar com alguém" ] ]
    )
    expect(brief["summary"]).to include("precisa_estorno", "Maria", "quero falar com alguém")
  end

  it "guarda no brief só as 6 mensagens mais recentes" do
    ticket = receive_message.ticket
    (2..8).each { |n| receive_message(provider_message_id: "wamid.#{n}", text: "mensagem #{n}") }

    brief = escalate(ticket.reload).handoff_brief

    expect(brief["message_count"]).to eq(8)
    expect(brief["recent_messages"].map { |m| m["seq"] }).to eq((3..8).to_a)
  end

  it "usa o prazo da prioridade do ticket" do
    travel_to(opened_at)
    ticket = receive_message.ticket
    ticket.update!(priority: "p1")

    expect(escalate(ticket).first_response_due_at).to eq(opened_at + 5.minutes)
  end

  it "recusa escalar quando a marca não tem fila padrão, sem gravar nada" do
    ticket = receive_message.ticket
    TicketQueue.update_all(default: false)

    expect { escalate(ticket) }.to raise_error(Handoff::Escalate::NoDefaultQueue)
    expect(ticket.reload).to have_attributes(mode: "ai", handoff_epoch: 0)
    expect(ConversationEvent.where(kind: "ticket.escalated")).to be_empty
  end
end
