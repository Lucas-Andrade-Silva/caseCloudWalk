require "rails_helper"

RSpec.describe Load::BurstPlan do
  it "gera mensagens sintéticas determinísticas pela seed" do
    first = described_class.build(count: 50, redeliver: 0.2, seed: 7)

    expect(described_class.build(count: 50, redeliver: 0.2, seed: 7)).to eq(first)
    expect(described_class.build(count: 50, redeliver: 0.2, seed: 8)).not_to eq(first)
  end

  it "manda a quantidade pedida de mensagens novas e reentrega perto da fração pedida" do
    plan = described_class.build(count: 1000, redeliver: 0.2, seed: 1)
    fresh = plan.reject { |item| item[:redelivery] }
    redeliveries = plan.select { |item| item[:redelivery] }

    expect(fresh.size).to eq(1000)
    expect(fresh.map { |item| item[:provider_message_id] }.uniq.size).to eq(1000)
    expect(redeliveries.size / 1000.0).to be_within(0.04).of(0.2)
    expect(redeliveries.map { |item| item[:provider_message_id] }).to all(be_in(fresh.map { |item| item[:provider_message_id] }))
  end

  it "reentrega sempre depois do envio original" do
    plan = described_class.build(count: 200, redeliver: 0.5, seed: 3)

    plan.each_with_index.select { |item, _| item[:redelivery] }.each do |item, index|
      original = plan.index { |other| other[:provider_message_id] == item[:provider_message_id] && !other[:redelivery] }
      expect(original).to be < index
    end
  end

  it "espalha as mensagens entre marcas e canais, com clientes que voltam a escrever" do
    plan = described_class.build(count: 400, redeliver: 0, seed: 5)

    expect(plan.map { |item| item[:brand] }.uniq).to contain_exactly("infinitepay", "jim")
    expect(plan.map { |item| item[:channel] }.uniq).to contain_exactly("app_chat", "whatsapp", "email")
    expect(plan.map { |item| item[:customer] }.uniq.size).to be < 400
  end
end
