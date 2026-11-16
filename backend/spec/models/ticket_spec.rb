require "rails_helper"

RSpec.describe Ticket do
  before { create_brand }

  describe "#append_message!" do
    it "numera pelo estado atual do banco, não pela cópia em memória" do
      ticket = receive_message.ticket
      # Dois processos carregaram o mesmo ticket quando ele tinha uma mensagem.
      stale_copy = described_class.find(ticket.id)

      second = ticket.append_message!(sender: "customer", body: "segunda")
      third = stale_copy.append_message!(sender: "customer", body: "terceira")

      expect([ second.seq, third.seq ]).to eq([ 2, 3 ])
      expect(ticket.reload.last_seq).to eq(3)
    end
  end

  it "não permite dois tickets abertos para o mesmo cliente, marca e canal" do
    ticket = receive_message.ticket

    expect {
      described_class.create!(brand: ticket.brand, customer: ticket.customer, channel: ticket.channel)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "permite um ticket novo depois que o anterior foi fechado" do
    ticket = receive_message.ticket
    ticket.update!(mode: "closed")

    reopened = receive_message(provider_message_id: "wamid.2").ticket

    expect(reopened.id).not_to eq(ticket.id)
    expect(reopened).to have_attributes(mode: "ai", last_seq: 1)
  end
end
