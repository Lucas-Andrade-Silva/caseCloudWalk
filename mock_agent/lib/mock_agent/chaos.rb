require "digest"

module MockAgent
  # Modo caos do agente simulado (ADR 0002, D6; spec 05). Faz o agente se comportar mal de propósito
  # para o experimento: atraso, duplicata, JSON quebrado, silêncio, ferramenta inventada e queda.
  #
  # Cada decisão sai do hash do event_id, então a mesma mensagem tem sempre o mesmo destino, inclusive
  # na reentrega. Configuração: MOCK_CHAOS="latency_ms=200..2000,duplicate=0.1,silence=0.05,...".
  module Chaos
    Config = Data.define(:latency_ms, :duplicate, :malformed, :silence, :invented_tool, :crash, :never_escalate)
    Plan = Data.define(:delay_ms, :duplicate, :malformed, :silence, :invented_tool, :crash)

    NONE = Config.new(latency_ms: 0..0, duplicate: 0.0, malformed: 0.0, silence: 0.0, invented_tool: 0.0,
                      crash: 0.0, never_escalate: false)
    FRACTIONS = %i[duplicate malformed silence invented_tool crash].freeze
    INVENTED_TOOL = "transferir_saldo"

    module_function

    def parse(text)
      return NONE if text.nil? || text.strip.empty?

      text.split(",").map(&:strip).reject(&:empty?).reduce(NONE) do |config, pair|
        key, value = pair.split("=", 2).map(&:strip)
        config.with(key.to_sym => parse_value(key, value))
      end
    end

    def parse_value(key, value)
      case key
      when "latency_ms"
        low, high = value.to_s.split("..", 2).map { |part| Integer(part, exception: false) }
        raise ArgumentError, "latency_ms precisa ser min..max, veio #{value.inspect}" unless low && high && low.between?(0, high)

        low..high
      when "never_escalate" then value == "true"
      when *FRACTIONS.map(&:to_s)
        fraction = Float(value, exception: false)
        raise ArgumentError, "#{key} precisa estar entre 0 e 1, veio #{value.inspect}" unless fraction&.between?(0, 1)

        fraction
      else
        raise ArgumentError, "chave de caos desconhecida: #{key}"
      end
    end

    def plan(event_id, config)
      span = config.latency_ms.size
      delay = config.latency_ms.min + (span > 1 ? (fraction("latency", event_id) * span).floor : 0)
      Plan.new(
        delay_ms: delay,
        **FRACTIONS.to_h { |effect| [ effect, fraction(effect, event_id) < config.public_send(effect) ] }
      )
    end

    # O que vai para o Kafka: a resposta, a resposta com uma ferramenta que não existe ou JSON quebrado.
    def payload_for(reply, plan)
      return %({"agent_turn_id": "#{reply['agent_turn_id']}", "text": quebrado) if plan.malformed

      reply = reply.merge("action" => "call_tool", "tool" => INVENTED_TOOL) if plan.invented_tool
      JSON.generate(reply)
    end

    # Número em [0, 1), independente para cada efeito.
    def fraction(effect, event_id)
      Digest::SHA256.digest("chaos:#{effect}:#{event_id}").unpack1("Q>") / 2.0**64
    end
  end
end
