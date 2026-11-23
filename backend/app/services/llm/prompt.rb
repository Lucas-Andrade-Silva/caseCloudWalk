module Llm
  # Prompt versionado no git (prompts/<tarefa>/vN.yaml): texto, schema, modelo e temperatura fixos (playbook §5).
  Prompt = Data.define(:task, :version, :model, :temperature, :max_tokens, :system, :schema) do
    CURRENT = { "enrich" => "v2", "brief" => "v2", "closing" => "v2", "incident" => "v1" }.freeze

    def self.load(task)
      file = Rails.root.join("prompts", task, "#{CURRENT.fetch(task)}.yaml")
      data = YAML.safe_load_file(file)
      new(task: task, version: data.fetch("version"), model: data.fetch("model"),
          temperature: data.fetch("temperature"), max_tokens: data.fetch("max_tokens"),
          system: data.fetch("system"), schema: data.fetch("schema"))
    end
  end
end
