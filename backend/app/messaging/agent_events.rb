# Eventos que a plataforma envia ao agente de IA. São gravados no outbox, na mesma transação da
# mudança que os originou, e seguem pelo caminho webhook -> broker -> Kafka.
module AgentEvents
  TOPIC = "helpdesk.messages"

  module_function

  def message_created!(ticket:, message:)
    OutboxEvent.create!(
      topic: TOPIC,
      key: ticket.id,
      headers: { "brand_id" => ticket.brand.slug },
      payload: {
        type: "message.created",
        ticket_id: ticket.id,
        brand: ticket.brand.slug,
        channel: ticket.channel,
        mode: ticket.mode,
        handoff_epoch: ticket.handoff_epoch,
        customer: { id: ticket.customer_id, external_id: ticket.customer.external_id },
        message: {
          id: message.id,
          seq: message.seq,
          sender: message.sender,
          text: message.body,
          created_at: message.created_at.iso8601(3)
        },
        # O que a plataforma lembra dos contatos anteriores do cliente na marca (ADR 0006).
        memory: Memory::Recall.call(ticket: ticket)
      }
    )
  end

  # Avisa o agente que o ticket saiu da IA, para ele parar de atender.
  def ticket_escalated!(ticket:)
    OutboxEvent.create!(
      topic: TOPIC,
      key: ticket.id,
      headers: { "brand_id" => ticket.brand.slug },
      payload: {
        type: "ticket.escalated",
        ticket_id: ticket.id,
        brand: ticket.brand.slug,
        mode: ticket.mode,
        handoff_epoch: ticket.handoff_epoch,
        trigger: ticket.escalation_trigger,
        reason: ticket.escalation_reason
      }
    )
  end
end
