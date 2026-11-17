require "rails_helper"

RSpec.describe Rules::Evaluator do
  let(:facts) do
    {
      "brand" => "infinitepay", "channel" => "whatsapp", "stage" => "opening",
      "message_text" => "Preciso de um EMPRÉSTIMO urgente", "customer_recurring" => true,
      "contacts_24h" => 3, "amount" => 5000.0, "escalation_reason" => nil
    }
  end

  def leaf(fact, op, value) = { "fact" => fact, "op" => op, "value" => value }
  def match?(condition) = described_class.matches?(condition, facts)

  it "avalia cada operador" do
    expect(match?(leaf("channel", "eq", "whatsapp"))).to be(true)
    expect(match?(leaf("channel", "neq", "whatsapp"))).to be(false)
    expect(match?(leaf("channel", "in", %w[email whatsapp]))).to be(true)
    expect(match?(leaf("contacts_24h", "gt", 2))).to be(true)
    expect(match?(leaf("contacts_24h", "gte", 3))).to be(true)
    expect(match?(leaf("contacts_24h", "lt", 3))).to be(false)
    expect(match?(leaf("contacts_24h", "lte", 3))).to be(true)
    expect(match?(leaf("amount", "eq", 5000))).to be(true)
    expect(match?(leaf("customer_recurring", "eq", true))).to be(true)
  end

  it "compara palavras-chave sem diferenciar maiúsculas nem acentos" do
    expect(match?(leaf("message_text", "contains_any", %w[emprestimo]))).to be(true)
    expect(match?(leaf("message_text", "contains_any", [ "Urgênte" ]))).to be(true)
    expect(match?(leaf("message_text", "contains_any", %w[maquininha pix]))).to be(false)
  end

  it "trata fato ausente como falso, inclusive em neq" do
    expect(match?(leaf("escalation_reason", "eq", "x"))).to be(false)
    expect(match?(leaf("escalation_reason", "neq", "x"))).to be(false)
    expect(match?(leaf("ai_minutes", "gt", 0))).to be(false)
  end

  it "combina all e any aninhados" do
    condition = {
      "all" => [
        leaf("brand", "eq", "infinitepay"),
        { "any" => [ leaf("channel", "eq", "email"), leaf("amount", "gte", 1000) ] }
      ]
    }

    expect(match?(condition)).to be(true)
    expect(match?({ "all" => [ condition, leaf("stage", "eq", "escalation") ] })).to be(false)
  end

  it "trata condição vazia como sempre verdadeira" do
    expect(match?({})).to be(true)
    expect(match?({ "all" => [] })).to be(true)
  end

  it "escolhe a primeira regra que bate, na ordem da lista" do
    rules = [
      { "id" => "email", "when" => leaf("channel", "eq", "email"), "then" => { "priority" => "p4" } },
      { "id" => "valor", "when" => leaf("amount", "gte", 1000), "then" => { "priority" => "p1" } },
      { "id" => "todas", "when" => {}, "then" => { "priority" => "p3" } }
    ]

    expect(described_class.first_match(rules, facts)["id"]).to eq("valor")
    expect(described_class.first_match(rules.first(1), facts)).to be_nil
  end
end
