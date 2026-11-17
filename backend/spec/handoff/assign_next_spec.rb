require "rails_helper"

RSpec.describe Handoff::AssignNext do
  describe "sob concorrência" do
    # Threads usam conexões próprias; a transação do teste as esconderia umas das outras.
    self.use_transactional_tests = false

    before do
      PriorityLevel.ensure_defaults!
      create_brand
    end

    after { delete_domain_data }

    def in_parallel(analysts)
      start = Concurrent::CountDownLatch.new(1)
      threads = analysts.map do |analyst|
        Thread.new do
          start.wait
          described_class.call(analyst: analyst)
        end
      end
      start.count_down
      threads.map(&:value)
    end

    it "nunca entrega o mesmo ticket a dois analistas" do
      tickets = %w[c-1 c-2].map { |customer| escalated_ticket(customer) }
      analysts = %w[Ana Beto Caio Duda].map { |name| create_analyst(name) }

      results = in_parallel(analysts)

      assigned = results.compact.map(&:id)
      expect(assigned).to match_array(tickets.map(&:id))
      expect(results.count(nil)).to eq(2)
      expect(Ticket.pluck(:mode)).to all(eq("human"))
      expect(ConversationEvent.where(kind: "ticket.assigned").count).to eq(2)
    end
  end
end
