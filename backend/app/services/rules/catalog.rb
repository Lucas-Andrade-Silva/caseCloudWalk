module Rules
  # Lista fechada e tipada dos fatos que as regras podem usar (ADR 0005, R3) e dos operadores por tipo.
  # Fatos do LLM entram aqui na fatia de LLM, com origem e confiança.
  module Catalog
    FACTS = {
      "brand" => :string,
      "channel" => :string,
      "stage" => :string,
      "message_text" => :text,
      "customer_recurring" => :boolean,
      "contacts_24h" => :number,
      "amount" => :number,
      "escalation_reason" => :string,
      "escalation_trigger" => :string,
      "ai_minutes" => :number
    }.freeze

    OPERATORS = {
      string: %w[eq neq in],
      text: %w[contains_any],
      number: %w[eq gt gte lt lte],
      boolean: %w[eq]
    }.freeze
  end
end
