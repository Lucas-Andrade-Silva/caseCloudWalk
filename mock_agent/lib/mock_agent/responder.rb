require "digest"

module MockAgent
  # Decide a resposta para um evento da plataforma. Função pura: não fala com Kafka nem com rede.
  class Responder
    # Namespace fixo (arbitrário) para derivar o agent_turn_id por UUID v5.
    TURN_NAMESPACE = [ "6f1d1c9a4b7e4f0d9a3c2e5b8d7f6a10" ].pack("H*").freeze

    # Devolve a resposta (Hash) ou nil quando o evento não pede resposta.
    def reply_for(event, event_id:)
      return nil if event_id.to_s.empty?
      return nil unless answerable?(event)

      message = event["message"]
      {
        "agent_turn_id" => turn_id_for(event_id),
        "ticket_id" => event["ticket_id"],
        "in_reply_to_seq" => message["seq"],
        "handoff_epoch" => event["handoff_epoch"],
        "action" => "reply",
        "text" => text_for(event)
      }
    end

    private

    def answerable?(event)
      event.is_a?(Hash) &&
        event["type"] == "message.created" &&
        event["mode"] == "ai" &&
        event["message"].is_a?(Hash) &&
        event["message"]["sender"] == "customer"
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
