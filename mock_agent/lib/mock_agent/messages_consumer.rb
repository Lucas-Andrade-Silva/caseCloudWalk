module MockAgent
  # Consome as mensagens da plataforma e publica a resposta do agente, aplicando o modo caos quando
  # configurado (MOCK_CHAOS). Sem caos, a resposta sai na hora e o offset é confirmado depois do Kafka.
  #
  # Com atraso, a resposta é agendada e o offset é confirmado antes de ela sair: se o processo cair
  # nesse intervalo, a resposta se perde, como aconteceria com um agente real. A plataforma cobre isso
  # com o vigia do agente mudo.
  class MessagesConsumer < Karafka::BaseConsumer
    def consume
      messages.each do |message|
        event_id = message.headers["event_id"]
        reply = responder.reply_for(parse(message.raw_payload), event_id: event_id)
        plan = Chaos.plan(event_id.to_s, Config.chaos)

        if reply.nil?
          MockAgent.logger.info("mensagem ignorada (offset #{message.offset})")
        elsif plan.silence
          MockAgent.logger.info("caos: silêncio para #{reply['ticket_id']}")
        else
          deliver(reply, plan)
        end

        next mark_as_consumed(message) unless plan.crash && reply

        # Confirma de forma síncrona antes de cair, para a reentrega não repetir a queda para sempre.
        mark_as_consumed!(message)
        MockAgent.logger.warn("caos: queda simulada do agente")
        Process.kill("KILL", Process.pid)
      end
    end

    private

    def deliver(reply, plan)
      message = { topic: Config.replies_topic, key: reply["ticket_id"], payload: Chaos.payload_for(reply, plan) }
      copies = plan.duplicate ? 2 : 1

      if plan.delay_ms.positive?
        copies.times { MockAgent.delayed_publisher.schedule(plan.delay_ms / 1000.0, message) }
      else
        copies.times { Karafka.producer.produce_sync(message) }
      end
    end

    def responder
      escalation_rate = Config.chaos.never_escalate ? 0.0 : Config.escalation_rate
      @responder ||= Responder.new(escalation_rate: escalation_rate)
    end

    def parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end
end
