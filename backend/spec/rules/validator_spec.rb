require "rails_helper"

RSpec.describe Rules::Validator do
  let(:brand) { create_brand }

  before do
    brand
    create_brand("jim")
  end

  def rule(overrides = {})
    {
      "id" => "credito", "name" => "Crédito",
      "when" => { "fact" => "message_text", "op" => "contains_any", "value" => [ "crédito" ] },
      "then" => { "queue" => "infinitepay-atendimento", "priority" => "p2", "tags" => [ "credito" ] }
    }.merge(overrides)
  end

  def errors_for(rules) = described_class.errors(rules, brand: brand)

  it "aceita uma lista válida" do
    expect(errors_for([ rule, rule("id" => "todas", "when" => {}, "then" => { "priority" => "p3" }) ])).to eq([])
  end

  it "aponta cada problema com o caminho" do
    cases = {
      [ rule("when" => { "fact" => "humor", "op" => "eq", "value" => "x" }) ] => "rules[0].when.fact",
      [ rule("when" => { "fact" => "channel", "op" => "gte", "value" => "x" }) ] => "rules[0].when.op",
      [ rule("when" => { "fact" => "amount", "op" => "gte", "value" => "mil" }) ] => "rules[0].when.value",
      [ rule("when" => { "fact" => "channel", "op" => "in", "value" => [] }) ] => "rules[0].when.value",
      [ rule("when" => { "all" => [ { "fact" => "channel", "op" => "eq" } ] }) ] => "rules[0].when.all[0].value",
      [ rule("then" => { "queue" => "jim-atendimento" }) ] => "rules[0].then.queue",
      [ rule("then" => { "queue" => "nao-existe" }) ] => "rules[0].then.queue",
      [ rule("then" => { "priority" => "p9" }) ] => "rules[0].then.priority",
      [ rule("then" => { "tags" => [ "Com Espaço" ] }) ] => "rules[0].then.tags",
      [ rule("then" => {}) ] => "rules[0].then",
      [ rule("id" => "ID Ruim") ] => "rules[0].id",
      [ rule, rule ] => "rules[1].id",
      [ rule("name" => "") ] => "rules[0].name"
    }

    cases.each do |rules, path|
      expect(errors_for(rules).map { |error| error[:path] }).to include(path), "esperava erro em #{path}"
    end
  end

  it "recusa árvore funda demais e listas grandes demais" do
    deep = { "fact" => "channel", "op" => "eq", "value" => "email" }
    6.times { deep = { "all" => [ deep ] } }

    expect(errors_for([ rule("when" => deep) ]).map { |e| e[:path] }).to include("rules[0].when")
    many = Array.new(101) { |n| rule("id" => "r-#{n}") }
    expect(errors_for(many).map { |e| e[:path] }).to include("rules")
  end

  it "recusa o que não é uma lista de objetos" do
    expect(errors_for("texto").map { |e| e[:path] }).to eq([ "rules" ])
    expect(errors_for([ "texto" ]).map { |e| e[:path] }).to eq([ "rules[0]" ])
  end
end
