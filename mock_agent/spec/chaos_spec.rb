require "spec_helper"

RSpec.describe MockAgent::Chaos do
  def ids(count) = Array.new(count) { |n| format("0193a7c2-0000-7000-8000-%012d", n) }

  describe ".parse" do
    it "lê a configuração chave=valor" do
      config = described_class.parse("latency_ms=200..2000, duplicate=0.1,malformed=0.02,silence=0.05," \
                                     "invented_tool=0.02,crash=0.01,never_escalate=true")

      expect(config).to have_attributes(latency_ms: 200..2000, duplicate: 0.1, malformed: 0.02, silence: 0.05,
                                        invented_tool: 0.02, crash: 0.01, never_escalate: true)
    end

    it "sem configuração, não há caos" do
      expect(described_class.parse(nil)).to eq(described_class::NONE)
      expect(described_class.parse("")).to eq(described_class::NONE)
    end

    it "recusa chave desconhecida, fração fora de 0 a 1 e intervalo inválido" do
      expect { described_class.parse("explode=0.5") }.to raise_error(ArgumentError, /explode/)
      expect { described_class.parse("duplicate=1.5") }.to raise_error(ArgumentError, /duplicate/)
      expect { described_class.parse("latency_ms=500..100") }.to raise_error(ArgumentError, /latency_ms/)
    end
  end

  describe ".plan" do
    let(:config) { described_class.parse("latency_ms=100..300,duplicate=0.2,malformed=0.1,silence=0.1,invented_tool=0.1,crash=0.05") }

    it "é determinístico pelo event_id" do
      first = ids(200).map { |id| described_class.plan(id, config) }

      expect(ids(200).map { |id| described_class.plan(id, config) }).to eq(first)
    end

    it "aplica cada efeito perto da fração configurada e atraso dentro do intervalo" do
      plans = ids(4000).map { |id| described_class.plan(id, config) }

      { duplicate: 0.2, malformed: 0.1, silence: 0.1, invented_tool: 0.1, crash: 0.05 }.each do |effect, rate|
        observed = plans.count(&effect) / 4000.0
        expect(observed).to be_within(0.03).of(rate), "#{effect}: #{observed}"
      end
      expect(plans.map(&:delay_ms)).to all(be_between(100, 300))
    end

    it "sem caos, responde na hora, uma vez e bem formado" do
      plan = described_class.plan(ids(1).first, described_class::NONE)

      expect(plan).to have_attributes(delay_ms: 0, duplicate: false, malformed: false, silence: false,
                                      invented_tool: false, crash: false)
    end
  end

  describe ".payload_for" do
    let(:reply) { { "agent_turn_id" => "t-1", "ticket_id" => "x", "action" => "reply", "text" => "oi" } }

    it "troca a ação por uma ferramenta inventada ou estraga o JSON" do
      plain = described_class::Plan.new(delay_ms: 0, duplicate: false, malformed: false, silence: false,
                                        invented_tool: false, crash: false)

      expect(JSON.parse(described_class.payload_for(reply, plain))).to eq(reply)
      expect(JSON.parse(described_class.payload_for(reply, plain.with(invented_tool: true))))
        .to include("action" => "call_tool", "tool" => "transferir_saldo")
      expect { JSON.parse(described_class.payload_for(reply, plain.with(malformed: true))) }.to raise_error(JSON::ParserError)
    end
  end
end

RSpec.describe MockAgent::DelayedPublisher do
  it "publica cada item no seu horário, na ordem do horário e não na de chegada" do
    published = Queue.new
    publisher = described_class.new { |item| published << item }

    publisher.schedule(0.3, "lento")
    publisher.schedule(0.05, "rápido")
    publisher.schedule(0, "imediato")

    expect(Array.new(3) { published.pop(timeout: 2) }).to eq(%w[imediato rápido lento])
  ensure
    publisher&.stop
  end
end
