module Llm
  # Confere a saída do LLM contra o schema do prompt. Cobre o que os nossos schemas usam: objeto plano, campos
  # obrigatórios, sem campos extras, enum, tipo, mínimo e máximo. Mesmo com saída estrita no Groq, quem decide
  # se aceita é a plataforma.
  module Schema
    TYPES = { "string" => String, "number" => Numeric, "integer" => Integer, "boolean" => [ TrueClass, FalseClass ] }.freeze

    module_function

    def valid?(schema, data)
      return false unless data.is_a?(Hash)
      return false unless (schema["required"] || []).all? { |key| data.key?(key) }

      properties = schema["properties"] || {}
      return false if schema["additionalProperties"] == false && (data.keys - properties.keys).any?

      data.all? { |key, value| property_valid?(properties[key], value) }
    end

    def property_valid?(rule, value)
      return false unless rule
      return false unless Array(TYPES.fetch(rule["type"])).any? { |type| value.is_a?(type) }
      return false if rule["enum"] && !rule["enum"].include?(value)
      return false if rule["minimum"] && value < rule["minimum"]
      return false if rule["maximum"] && value > rule["maximum"]
      return false if rule["maxLength"] && value.length > rule["maxLength"]

      true
    end
  end
end
