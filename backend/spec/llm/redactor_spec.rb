require "rails_helper"

RSpec.describe Llm::Redactor do
  it "troca CPF válido, cartão que passa no Luhn, e-mail e telefone por marcadores" do
    text = "Sou o João, CPF 529.982.247-25, cartão 4111 1111 1111 1111, joao.silva@exemplo.com, " \
           "fone (11) 98765-4321 ou +55 11 3333-4444."

    result = described_class.call(text)

    expect(result.text).to eq("Sou o João, CPF [CPF], cartão [CARTAO], [EMAIL], fone [TELEFONE] ou [TELEFONE].")
    expect(result.findings).to eq("cpf" => 1, "card" => 1, "email" => 1, "phone" => 2)
  end

  it "não apaga números que só parecem CPF ou cartão, como valores e protocolos" do
    text = "Quero R$ 12.000,00 de empréstimo; protocolo 123.456.789-00; pedido 4111 1111 1111 1112."

    result = described_class.call(text)

    expect(result.text).to eq(text)
    expect(result.findings).to eq({})
  end

  it "aceita CPF sem pontuação" do
    expect(described_class.call("cpf 52998224725").text).to eq("cpf [CPF]")
  end
end
