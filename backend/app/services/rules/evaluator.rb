module Rules
  # Avalia regras sobre um conjunto de fatos. Função pura: não lê banco nem relógio.
  module Evaluator
    module_function

    # A primeira regra da lista cujo `when` bate, ou nil.
    def first_match(rules, facts)
      rules.find { |rule| matches?(rule["when"], facts) }
    end

    def matches?(node, facts)
      return true if node.blank?
      return node["all"].all? { |child| matches?(child, facts) } if node.key?("all")
      return node["any"].any? { |child| matches?(child, facts) } if node.key?("any")

      leaf_matches?(node, facts)
    end

    # Fato ausente torna a condição falsa, qualquer que seja o operador.
    def leaf_matches?(node, facts)
      actual = facts[node["fact"]]
      expected = node["value"]
      return false if actual.nil?

      case node["op"]
      when "eq" then actual == expected
      when "neq" then actual != expected
      when "in" then Array(expected).include?(actual)
      when "gt" then actual > expected
      when "gte" then actual >= expected
      when "lt" then actual < expected
      when "lte" then actual <= expected
      when "contains_any"
        text = normalize(actual)
        Array(expected).any? { |word| text.include?(normalize(word)) }
      else false
      end
    end

    # Sem acento e sem caixa: "Empréstimo" bate com "emprestimo".
    def normalize(text) = I18n.transliterate(text.to_s.downcase)
  end
end
