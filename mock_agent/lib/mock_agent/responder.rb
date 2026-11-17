require "digest"

module MockAgent
  # Decide a resposta para um evento da plataforma. Função pura: não fala com Kafka nem com rede.
  #
  # Escala uma fração das mensagens (`escalation_rate`, ADR 0002, D6). A decisão sai do hash do
  # event_id, então é determinística: a mesma mensagem decide sempre igual, inclusive na reentrega.
  # As marcas "[escalar]" e "[responder]" no texto forçam a decisão, para demos e cenários de teste.
  class Responder
    # Namespace fixo (arbitrário) para derivar o agent_turn_id por UUID v5.
    TURN_NAMESPACE = [ "6f1d1c9a4b7e4f0d9a3c2e5b8d7f6a10" ].pack("H*").freeze
    FORCE_ESCALATE = "[escalar]"
    FORCE_REPLY = "[responder]"
    REASONS = %w[precisa_analise_humana pedido_de_estorno duvida_sobre_credito problema_no_dispositivo].freeze

    def initialize(escalation_rate: 0.0)
      rate = Float(escalation_rate)
      raise ArgumentError, "escalation_rate precisa estar entre 0 e 1, veio #{rate}" unless rate.between?(0, 1)

      @escalation_rate = rate
    end

    # Devolve a resposta (Hash) ou nil quando o evento não pede resposta.
    def reply_for(event, event_id:)
      return nil if event_id.to_s.empty?
      return nil unless answerable?(event)

      message = event["message"]
      base = {
        "agent_turn_id" => turn_id_for(event_id),
        "ticket_id" => event["ticket_id"],
        "in_reply_to_seq" => message["seq"],
        "handoff_epoch" => event["handoff_epoch"]
      }

      if escalate?(message["text"].to_s, event_id)
        base.merge("action" => "escalate", "reason" => reason_for(event_id),
                   "text" => "Vou te passar para um especialista da nossa equipe. Ele já recebe o histórico da conversa.")
      else
        base.merge("action" => "reply", "text" => text_for(event))
      end
    end

    private

    def answerable?(event)
      event.is_a?(Hash) &&
        event["type"] == "message.created" &&
        event["mode"] == "ai" &&
        event["message"].is_a?(Hash) &&
        event["message"]["sender"] == "customer"
    end

    def escalate?(text, event_id)
      return true if text.include?(FORCE_ESCALATE)
      return false if text.include?(FORCE_REPLY)

      fraction(event_id) < @escalation_rate
    end

    # Número em [0, 1) derivado do event_id.
    def fraction(event_id)
      Digest::SHA256.digest("escalate:#{event_id}").unpack1("Q>") / 2.0**64
    end

    def reason_for(event_id)
      REASONS[Digest::SHA256.digest("reason:#{event_id}").unpack1("N") % REASONS.size]
    end

    # O mesmo event_id gera sempre o mesmo agent_turn_id. Assim, se o Kafka entregar a mensagem
    # duas vezes, a plataforma reconhece a segunda resposta como repetição da primeira.
    def turn_id_for(event_id)
      bytes = Digest::SHA1.digest(TURN_NAMESPACE + event_id.to_s).bytes.first(16)
      bytes[6] = (bytes[6] & 0x0f) | 0x50 # versão 5
      bytes[8] = (bytes[8] & 0x3f) | 0x80 # variante RFC 4122
      hex = bytes.pack("C*").unpack1("H*")
      [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
    end

    def text_for(event)
      "Olá! Sou o assistente virtual da #{event['brand']}. " \
        "Recebi sua mensagem (nº #{event['message']['seq']}) e já estou verificando."
    end
  end
end
