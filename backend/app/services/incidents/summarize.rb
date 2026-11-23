module Incidents
  # Título e rascunho de resposta pela LLM (ADR 0009, W1). Lê as primeiras mensagens dos clientes do incidente,
  # redigidas pelo cliente LLM. Sem LLM, ficam os do template.
  module Summarize
    SAMPLE = 10

    module_function

    def call(incident, client: Llm.client)
      result = client.call(task: "incident", input: input(incident))
      return incident unless result.ok

      incident.update!(title: result.data["title"], draft_reply: result.data["draft_reply"],
                       title_source: result.source, prompt_version: result.prompt_version, model: result.model)
      incident
    end

    def input(incident)
      language = incident.brand.slug == "jim" ? "inglês" : "português"
      messages = Message.joins(:ticket).where(tickets: { incident_id: incident.id }, sender: "customer")
                        .order(:created_at).limit(SAMPLE).pluck(:body)
      [ "Marca: #{incident.brand.name} (responda em #{language})", "Grupo: #{incident.label}",
        "Mensagens dos clientes:", *messages.map { |body| "- #{body}" } ].join("\n")
    end
  end
end
