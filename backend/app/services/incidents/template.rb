module Incidents
  # Título e rascunho sem LLM: o incidente já nasce útil, e a LLM só melhora o texto (ADR 0009).
  module Template
    module_function

    def title(brand, label) = "Pico de #{label} na #{brand.name}"

    def draft_reply(brand, label)
      if brand.slug == "jim"
        "Hi! We are aware of an issue affecting #{label} and our team is already working on it. " \
          "We will update you here as soon as it is resolved."
      else
        "Olá! Identificamos uma instabilidade em #{label} e o nosso time já está trabalhando nisso. " \
          "Avisamos por aqui assim que normalizar."
      end
    end
  end
end
