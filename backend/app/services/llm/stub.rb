module Llm
  # Resposta sem rede para testes e carga (playbook §5): determinística pelo texto, sempre no schema. Não tenta
  # ser inteligente: é um substituto previsível. Latência e falha injetáveis para os cenários do experimento
  # (LLM_STUB_LATENCY_MS e LLM_STUB_FAILURE_RATE, esta decidida pelo hash do texto).
  module Stub
    class InjectedFailure < StandardError; end

    CATEGORY_WORDS = {
      "credito" => /empr[ée]stimo|cr[ée]dito|limite|loan|credit/i,
      "maquininha" => /maquininha|m[áa]quina|bateria|n[ãa]o liga|card reader|turn on/i,
      "repasse" => /repasse|payout|n[ãa]o caiu|n[ãa]o recebi/i,
      "pagamentos_pix" => /pix|cobra|charged|pagamento/i,
      "conta_cadastro" => /senha|cadastro|conta banc|bank account|boleto/i,
      "falar_com_humano" => /atendente|pessoa|humano|person/i
    }.freeze
    ENGLISH = /\b(the|my|is|where|want|need|charged|turn)\b/i
    ANGRY = /!|absurdo|p[ée]ssimo|urgente|rid[íi]culo|terrible/i

    module_function

    def respond(task, text)
      inject_latency_and_failure(text)
      case task
      when "enrich" then enrich(text)
      when "brief", "closing" then { "summary" => "Resumo de teste: #{text.to_s.lines.first.to_s.strip[0, 120]}" }
      end
    end

    def enrich(text)
      category = CATEGORY_WORDS.find { |_, pattern| pattern.match?(text) }&.first || "outro"
      { "category" => category, "language" => ENGLISH.match?(text) ? "en" : "pt",
        "frustration" => ANGRY.match?(text) ? "alta" : "baixa", "confidence" => 0.6 }
    end

    def inject_latency_and_failure(text)
      latency = Integer(ENV.fetch("LLM_STUB_LATENCY_MS", "0"))
      sleep(latency / 1000.0) if latency.positive?
      rate = Float(ENV.fetch("LLM_STUB_FAILURE_RATE", "0"))
      fraction = Digest::SHA256.digest("stub-failure:#{text}").unpack1("Q>") / 2.0**64
      raise InjectedFailure, "falha injetada no stub" if fraction < rate
    end
  end
end
