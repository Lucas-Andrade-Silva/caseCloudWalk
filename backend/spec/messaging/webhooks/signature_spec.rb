require "rails_helper"

RSpec.describe Webhooks::Signature do
  let(:now) { Time.utc(2026, 11, 15, 12, 0, 0) }
  let(:attrs) { { id: "evt-1", timestamp: now.to_i, body: '{"a":1}' } }
  let(:signature) { described_class.sign(**attrs, secret: "s3gredo") }

  def valid?(overrides = {})
    described_class.valid?(**attrs.merge(signature: signature, secrets: [ "s3gredo" ], now: now).merge(overrides))
  end

  it "assina com HMAC-SHA256 sobre id.timestamp.corpo, no formato v1=<hex>" do
    expected = OpenSSL::HMAC.hexdigest("SHA256", "s3gredo", "evt-1.#{now.to_i}.{\"a\":1}")

    expect(signature).to eq("v1=#{expected}")
  end

  it "aceita a assinatura correta" do
    expect(valid?).to be(true)
  end

  it "recusa quando id, timestamp, corpo ou segredo mudam" do
    expect(valid?(id: "evt-2")).to be(false)
    expect(valid?(body: '{"a":2}')).to be(false)
    expect(valid?(secrets: [ "outro" ])).to be(false)
    expect(valid?(timestamp: now.to_i + 1)).to be(false)
  end

  it "aceita até 5 minutos de diferença de relógio, para os dois lados" do
    expect(valid?(now: now + 300)).to be(true)
    expect(valid?(now: now - 300)).to be(true)
    expect(valid?(now: now + 301)).to be(false)
    expect(valid?(now: now - 301)).to be(false)
  end

  it "recusa valores ausentes ou malformados sem levantar erro" do
    expect(valid?(signature: nil)).to be(false)
    expect(valid?(signature: "v1=")).to be(false)
    expect(valid?(id: nil)).to be(false)
    expect(valid?(timestamp: "ontem")).to be(false)
    expect(valid?(secrets: [])).to be(false)
  end
end
