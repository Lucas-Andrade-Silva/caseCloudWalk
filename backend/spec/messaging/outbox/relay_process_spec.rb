require "rails_helper"

RSpec.describe Outbox::RelayProcess do
  # Relay falso: cada chamada consome o próximo resultado do roteiro (número publicado ou erro).
  let(:relay) do
    Class.new do
      attr_reader :calls

      def initialize(script)
        @script = script
        @calls = 0
      end

      def publish_pending
        @calls += 1
        result = @script.shift || 0
        raise result if result.is_a?(Exception)

        result
      end
    end
  end

  let(:lock) do
    Class.new do
      attr_accessor :available
      attr_reader :released

      def initialize
        @available = true
        @released = false
      end

      def acquire = available
      def release = @released = true
    end.new
  end

  let(:pauses) { [] }
  let(:log) { StringIO.new }

  # Roda o laço até a enésima pausa. Sem relógio real: a pausa só é registrada.
  def run_process(script, stop_after_pauses:)
    fake_relay = relay.new(script)
    process = nil
    sleeper = lambda do |seconds|
      pauses << seconds
      process.stop if pauses.size >= stop_after_pauses
    end
    process = described_class.new(
      relay: fake_relay,
      lock_factory: ->(_connection) { lock },
      sleeper: sleeper,
      logger: Logger.new(log),
      random: Random.new(42)
    )
    process.run
    fake_relay
  end

  it "publica lote após lote sem pausar e só descansa quando o outbox esvazia" do
    fake_relay = run_process([ 100, 100, 3, 0 ], stop_after_pauses: 1)

    expect(fake_relay.calls).to eq(4)
    expect(pauses).to eq([ described_class::IDLE_PAUSE ])
  end

  it "fica em espera, sem publicar, enquanto outro relay segura o lock" do
    lock.available = false

    fake_relay = run_process([ 5 ], stop_after_pauses: 2)

    expect(fake_relay.calls).to eq(0)
    expect(pauses).to eq([ described_class::STANDBY_PAUSE ] * 2)
  end

  it "sobrevive a falhas de publicação com espera crescente e volta ao normal no sucesso" do
    script = [ RuntimeError.new("kafka fora"), RuntimeError.new("kafka fora"), 2, 0 ]

    fake_relay = run_process(script, stop_after_pauses: 3)

    expect(fake_relay.calls).to eq(4)
    first_backoff, second_backoff, idle = pauses
    expect(first_backoff).to be_between(0.5, 1.0)
    expect(second_backoff).to be_between(1.0, 2.0)
    expect(idle).to eq(described_class::IDLE_PAUSE)
    expect(log.string).to include("kafka fora")
  end

  it "limita a espera entre tentativas" do
    script = Array.new(12) { RuntimeError.new("kafka fora") }

    run_process(script, stop_after_pauses: 12)

    expect(pauses.max).to be <= described_class::MAX_BACKOFF
  end

  it "solta o lock ao parar" do
    run_process([ 0 ], stop_after_pauses: 1)

    expect(lock.released).to be(true)
  end
end
