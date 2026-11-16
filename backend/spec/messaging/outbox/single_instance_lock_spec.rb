require "rails_helper"

RSpec.describe Outbox::SingleInstanceLock do
  # Advisory lock de sessão: precisa de duas conexões reais, fora da transação do teste.
  self.use_transactional_tests = false

  let(:pool) { ActiveRecord::Base.connection_pool }

  it "só uma conexão segura o lock; ao soltar, a outra assume" do
    first_connection = pool.checkout
    second_connection = pool.checkout
    first = described_class.new(first_connection)
    second = described_class.new(second_connection)

    expect(first.acquire).to be(true)
    expect(second.acquire).to be(false)

    first.release
    expect(second.acquire).to be(true)
  ensure
    second&.release
    [ first_connection, second_connection ].compact.each { |connection| pool.checkin(connection) }
  end
end
