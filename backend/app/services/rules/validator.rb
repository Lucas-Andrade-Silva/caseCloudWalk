module Rules
  # Valida uma lista de regras antes de ela ser gravada. Devolve uma lista de erros
  # `{path:, message:}`; lista vazia significa válida. Nada aqui levanta exceção.
  class Validator
    MAX_RULES = 100
    MAX_DEPTH = 5
    RULE_ID = /\A[a-z0-9-]{1,64}\z/
    TAG = /\A[a-z0-9_-]{1,32}\z/

    def self.errors(rules, brand:) = new(brand).errors(rules)

    def initialize(brand)
      @brand = brand
      @errors = []
    end

    def errors(rules)
      return [ error("rules", "precisa ser uma lista de regras") ] unless rules.is_a?(Array)
      return [ error("rules", "no máximo #{MAX_RULES} regras") ] if rules.size > MAX_RULES

      seen_ids = []
      rules.each_with_index do |rule, index|
        path = "rules[#{index}]"
        next @errors << error(path, "cada regra precisa ser um objeto") unless rule.is_a?(Hash)

        check_id(rule["id"], "#{path}.id", seen_ids)
        @errors << error("#{path}.name", "é obrigatório") unless rule["name"].is_a?(String) && rule["name"].strip != ""
        check_when(rule["when"], "#{path}.when")
        check_then(rule["then"], "#{path}.then")
      end
      @errors
    end

    private

    def error(path, message) = { path: path, message: message }

    def check_id(id, path, seen_ids)
      if !id.is_a?(String) || !RULE_ID.match?(id)
        @errors << error(path, "precisa seguir [a-z0-9-]{1,64}")
      elsif seen_ids.include?(id)
        @errors << error(path, "repetido: #{id}")
      else
        seen_ids << id
      end
    end

    def check_when(node, path)
      return if node.nil? || node == {}
      return @errors << error(path, "precisa ser um objeto") unless node.is_a?(Hash)
      return @errors << error(path, "passa de #{MAX_DEPTH} níveis") if depth(node) > MAX_DEPTH

      check_node(node, path)
    end

    def check_node(node, path)
      return @errors << error(path, "precisa ser um objeto") unless node.is_a?(Hash)

      group = %w[all any].find { |key| node.key?(key) }
      return check_leaf(node, path) unless group

      children = node[group]
      return @errors << error("#{path}.#{group}", "precisa ser uma lista") unless children.is_a?(Array)

      children.each_with_index { |child, index| check_node(child, "#{path}.#{group}[#{index}]") }
    end

    def check_leaf(node, path)
      type = Catalog::FACTS[node["fact"]]
      return @errors << error("#{path}.fact", "fato desconhecido: #{node['fact'].inspect}") unless type

      operators = Catalog::OPERATORS.fetch(type)
      unless operators.include?(node["op"])
        return @errors << error("#{path}.op", "use #{operators.join(', ')} com #{node['fact']}")
      end

      @errors << error("#{path}.value", "valor inválido para #{node['op']}") unless valid_value?(type, node["op"], node["value"])
    end

    def valid_value?(type, op, value)
      case [ type, op ]
      in [ :string, "in" ] then non_empty_strings?(value)
      in [ :string, _ ] then value.is_a?(String)
      in [ :text, _ ] then non_empty_strings?(value)
      in [ :number, _ ] then value.is_a?(Numeric)
      in [ :boolean, _ ] then [ true, false ].include?(value)
      end
    end

    def non_empty_strings?(value)
      value.is_a?(Array) && value.any? && value.all? { |item| item.is_a?(String) && item.strip != "" }
    end

    def depth(node)
      return 1 unless node.is_a?(Hash)

      children = node["all"] || node["any"]
      return 1 unless children.is_a?(Array)

      1 + (children.map { |child| depth(child) }.max || 0)
    end

    def check_then(action, path)
      return @errors << error(path, "precisa ter queue, priority ou tags") unless action.is_a?(Hash)
      unless %w[queue priority tags].any? { |key| action.key?(key) }
        return @errors << error(path, "precisa ter queue, priority ou tags")
      end

      if action.key?("queue") && !TicketQueue.exists?(slug: action["queue"].to_s, brand_id: @brand.id)
        @errors << error("#{path}.queue", "fila inexistente na marca #{@brand.slug}: #{action['queue'].inspect}")
      end
      if action.key?("priority") && !PriorityLevel.exists?(code: action["priority"].to_s)
        @errors << error("#{path}.priority", "prioridade inexistente: #{action['priority'].inspect}")
      end
      if action.key?("tags") && !(action["tags"].is_a?(Array) && action["tags"].all? { |tag| tag.is_a?(String) && TAG.match?(tag) })
        @errors << error("#{path}.tags", "precisa ser uma lista de [a-z0-9_-]{1,32}")
      end
    end
  end
end
