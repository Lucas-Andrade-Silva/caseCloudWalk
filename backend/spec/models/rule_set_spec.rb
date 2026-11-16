require "rails_helper"

RSpec.describe RuleSet do
  let(:brand) { create_brand }
  let(:rules) { [ { "id" => "todas", "name" => "Todas", "when" => {}, "then" => { "priority" => "p3" } } ] }

  def draft(version) = described_class.create!(brand: brand, version: version, rules: rules)

  it "nasce rascunho e pode ser editado" do
    rule_set = draft(1)

    rule_set.update!(rules: rules.map { |rule| rule.merge("then" => { "priority" => "p4" }) })

    expect(rule_set.reload).to have_attributes(status: "draft", published_at: nil)
  end

  it "publicar arquiva a versão publicada anterior" do
    first = draft(1).tap(&:publish!)
    second = draft(2)

    second.publish!

    expect(first.reload.status).to eq("archived")
    expect(second.reload).to have_attributes(status: "published", published_at: be_present)
    expect(described_class.published_for(brand)).to eq(second)
  end

  it "não deixa mudar as regras de uma versão publicada ou arquivada" do
    published = draft(1).tap(&:publish!)

    expect { published.update!(rules: []) }.to raise_error(RuleSet::Immutable)
    published.reload
    expect { published.publish! }.to raise_error(RuleSet::Immutable)
  end

  it "não aceita dois publicados na mesma marca" do
    draft(1).tap(&:publish!)

    expect { draft(2).update_columns(status: "published") }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
