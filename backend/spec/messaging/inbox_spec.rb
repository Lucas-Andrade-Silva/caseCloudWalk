require "rails_helper"

RSpec.describe Inbox do
  let(:event_id) { SecureRandom.uuid_v7 }

  describe ".process" do
    it "executa o efeito uma única vez para o mesmo evento e consumidor" do
      effects = 0

      first = described_class.process(consumer: "replies", event_id: event_id) { effects += 1 }
      second = described_class.process(consumer: "replies", event_id: event_id) { effects += 1 }

      expect(first).to be(true)
      expect(second).to be(false)
      expect(effects).to eq(1)
      expect(ProcessedEvent.where(consumer_name: "replies", event_id: event_id).count).to eq(1)
    end

    it "trata consumidores diferentes de forma independente" do
      effects = []

      described_class.process(consumer: "replies", event_id: event_id) { effects << :replies }
      described_class.process(consumer: "enricher", event_id: event_id) { effects << :enricher }

      expect(effects).to eq(%i[replies enricher])
    end

    it "não registra o evento quando o efeito falha, e a nova tentativa executa" do
      expect {
        described_class.process(consumer: "replies", event_id: event_id) { raise "efeito falhou" }
      }.to raise_error("efeito falhou")

      expect(ProcessedEvent.count).to eq(0)

      effects = 0
      expect(described_class.process(consumer: "replies", event_id: event_id) { effects += 1 }).to be(true)
      expect(effects).to eq(1)
    end

    it "recusa evento sem identidade" do
      expect {
        described_class.process(consumer: "replies", event_id: nil) { }
      }.to raise_error(Inbox::MissingEventId)
    end
  end

  describe "sob concorrência" do
    # Threads usam conexões próprias; a transação do teste as esconderia umas das outras.
    self.use_transactional_tests = false

    after { ProcessedEvent.delete_all }

    it "duas entregas simultâneas do mesmo evento executam o efeito uma vez" do
      effects = Concurrent::AtomicFixnum.new(0)
      start = Concurrent::CountDownLatch.new(1)

      threads = Array.new(2) do
        Thread.new do
          start.wait
          described_class.process(consumer: "replies", event_id: event_id) do
            sleep 0.2 # segura a transação aberta para a outra thread colidir
            effects.increment
          end
        end
      end
      start.count_down
      results = threads.map(&:value)

      expect(effects.value).to eq(1)
      expect(results).to contain_exactly(true, false)
    end
  end
end
