module Llm
  # Tira dados pessoais do texto antes de qualquer chamada ao LLM (playbook §5), mesmo com dados sintéticos.
  # CPF só conta se o dígito verificador fecha e cartão só se passa no Luhn: assim valores e protocolos não
  # viram marcadores à toa.
  module Redactor
    Result = Data.define(:text, :findings)

    EMAIL = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/
    CARD = /(?<![\w])(?:\d[ -]?){12,18}\d(?![\w])/
    CPF = /(?<![\w.])\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?![\w])/
    PHONE = /(?<![\w])(?:\+55\s?)?(?:\(\d{2}\)\s?|\d{2}\s)?\d{4,5}-\d{4}(?![\w])/

    module_function

    def call(text)
      findings = Hash.new(0)
      redacted = text.to_s
                     .gsub(EMAIL) { findings["email"] += 1 and "[EMAIL]" }
                     .gsub(CARD) { |match| luhn?(match.delete("^0-9")) ? (findings["card"] += 1 and "[CARTAO]") : match }
                     .gsub(CPF) { |match| cpf?(match.delete("^0-9")) ? (findings["cpf"] += 1 and "[CPF]") : match }
                     .gsub(PHONE) { findings["phone"] += 1 and "[TELEFONE]" }
      Result.new(text: redacted, findings: findings.to_h)
    end

    def luhn?(digits)
      sum = digits.reverse.chars.each_with_index.sum do |char, index|
        value = char.to_i * (index.odd? ? 2 : 1)
        value > 9 ? value - 9 : value
      end
      (sum % 10).zero?
    end

    def cpf?(digits)
      return false unless digits.length == 11 && digits.chars.uniq.size > 1

      numbers = digits.chars.map(&:to_i)
      [ 9, 10 ].all? do |size|
        sum = numbers.first(size).each_with_index.sum { |number, index| number * (size + 1 - index) }
        check = (sum * 10) % 11 % 10
        check == numbers[size]
      end
    end
  end
end
