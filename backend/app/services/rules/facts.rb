module Rules
  # Monta os fatos de um ticket para as regras (ADR 0005, R3). Tudo é calculado em relação ao momento
  # do ticket, para que o dry-run sobre tickets antigos veja o que a regra teria visto na hora.
  module Facts
    # Valores em dinheiro: "R$ 5.000,00", "R$5000", "US$ 1,200.50", "$300".
    MONEY = /(?:R\$|US\$|\$)\s?(\d+(?:[.,]\d{3})*(?:[.,]\d{1,2})?)/i

    module_function

    def for_opening(ticket)
      first = ticket.messages.where(sender: "customer").order(:seq).first
      base(ticket).merge("stage" => "opening", "message_text" => first&.body, "amount" => amount_in(first&.body))
    end

    def for_escalation(ticket, trigger:, reason:, now: Time.current)
      text = ticket.messages.where(sender: "customer").order(:seq).pluck(:body).join("\n")
      base(ticket).merge(
        "stage" => "escalation",
        "message_text" => text,
        "amount" => amount_in(text),
        "escalation_trigger" => trigger,
        "escalation_reason" => reason,
        "ai_minutes" => ((now - ticket.created_at) / 60.0).round(1)
      )
    end

    def base(ticket)
      same_customer = Ticket.where(customer_id: ticket.customer_id)
      {
        "brand" => ticket.brand.slug,
        "channel" => ticket.channel,
        "customer_recurring" => same_customer.where(created_at: ...ticket.created_at).exists?,
        "contacts_24h" => same_customer.where(created_at: (ticket.created_at - 24.hours)..ticket.created_at).count
      }.merge(ticket.llm_facts.to_h.slice("category", "language", "frustration"))
    end

    # O maior valor em dinheiro citado no texto, ou nil.
    def amount_in(text)
      text.to_s.scan(MONEY).map { |(number)| parse_number(number) }.max
    end

    # O último separador é decimal se tiver 1 ou 2 dígitos depois dele ("120,50", "1,200.50");
    # os demais separadores são de milhar ("5.000", "1,200").
    def parse_number(number)
      last_separator = number.rindex(/[.,]/)
      if last_separator && number.length - last_separator - 1 <= 2
        "#{number[0...last_separator].delete('.,')}.#{number[(last_separator + 1)..]}".to_f
      else
        number.delete(".,").to_f
      end
    end
  end
end
