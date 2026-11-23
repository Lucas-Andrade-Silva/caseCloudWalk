require "rails_helper"

RSpec.describe Llm::Prompt do
  # Visto ao vivo em 2026-11-21: o gpt-oss-120b raciocina antes de responder. Com 200 tokens, uma mensagem com
  # tentativa de injeção esgotou o limite no raciocínio, a saída veio vazia e o Groq respondeu 400
  # (json_validate_failed). Com 1.000, respondeu certo e ignorou a injeção.
  it "reserva tokens para o raciocínio do modelo em todas as tarefas" do
    %w[enrich brief closing].each do |task|
      prompt = described_class.load(task)

      expect(prompt.max_tokens).to be >= 1000, "#{task} tem só #{prompt.max_tokens} tokens"
      expect(prompt.version).to eq("#{task}-v2")
    end
  end
end
