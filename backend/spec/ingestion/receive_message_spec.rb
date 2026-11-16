require "rails_helper"

RSpec.describe Ingestion::ReceiveMessage do
  describe "atomicidade" do
    before { create_brand }

    it "não grava nada quando o evento do outbox falha" do
      allow(OutboxEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "outbox fora")

      expect { receive_message }.to raise_error(ActiveRecord::StatementInvalid)

      expect([ InboundEvent.count, Customer.count, Ticket.count, Message.count, ConversationEvent.count ])
        .to eq([ 0, 0, 0, 0, 0 ])
    end

    it "não avisa o agente quando o ticket não está em modo ai" do
      first = receive_message
      first.ticket.update!(mode: "human")

      receive_message(provider_message_id: "wamid.2")

      expect(Message.count).to eq(2)
      expect(OutboxEvent.count).to eq(1)
    end
  end

  describe "sob concorrência" do
    # Threads usam conexões próprias; a transação do teste as esconderia umas das outras.
    self.use_transactional_tests = false

    before { create_brand }
    after { delete_domain_data }

    def in_parallel(count)
      start = Concurrent::CountDownLatch.new(1)
      threads = Array.new(count) do |index|
        Thread.new do
          start.wait
          yield index
        end
      end
      start.count_down
      threads.map(&:value)
    end

    it "dois webhooks idênticos simultâneos criam uma mensagem só" do
      results = in_parallel(2) { receive_message }

      expect(results.map(&:duplicate)).to contain_exactly(false, true)
      expect(results.map { |r| r.message.id }.uniq.size).to eq(1)
      expect([ Ticket.count, Message.count, OutboxEvent.count ]).to eq([ 1, 1, 1 ])
    end

    it "primeiras mensagens simultâneas do mesmo cliente caem num ticket só, com seq sem buraco" do
      in_parallel(4) { |index| receive_message(provider_message_id: "wamid.#{index}") }

      expect(Ticket.count).to eq(1)
      expect(Customer.count).to eq(1)
      expect(Message.order(:seq).pluck(:seq)).to eq([ 1, 2, 3, 4 ])
      expect(Ticket.sole.last_seq).to eq(4)
      expect(ConversationEvent.where(kind: "ticket.opened").count).to eq(1)
    end

    it "publica os eventos de um ticket no outbox na mesma ordem do seq" do
      in_parallel(4) { |index| receive_message(provider_message_id: "wamid.#{index}") }

      seqs_in_outbox_order = OutboxEvent.order(:id).map { |event| event.payload.dig("message", "seq") }
      expect(seqs_in_outbox_order).to eq([ 1, 2, 3, 4 ])
    end
  end
end
