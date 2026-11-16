require "rails_helper"

RSpec.describe Ticket, "máquina de estados" do
  before { create_brand }

  let(:ticket) { receive_message.ticket }

  allowed = {
    "ai" => %w[pending_human human closed],
    "pending_human" => %w[human],
    "human" => %w[closed],
    "closed" => []
  }

  allowed.each do |from, targets|
    (Ticket::MODES - [ from ]).each do |to|
      if targets.include?(to)
        it "permite #{from} -> #{to}" do
          ticket.update_columns(mode: from)

          ticket.transition_to!(to)

          expect(ticket.reload.mode).to eq(to)
        end
      else
        it "recusa #{from} -> #{to} sem gravar nada" do
          ticket.update_columns(mode: from)

          expect { ticket.transition_to!(to, priority: "p1") }.to raise_error(Ticket::InvalidTransition)
          expect(ticket.reload).to have_attributes(mode: from, priority: "p3")
        end
      end
    end
  end

  it "incrementa o handoff_epoch em toda troca de dono" do
    ticket.transition_to!("pending_human")
    ticket.transition_to!("human")

    expect(ticket.reload.handoff_epoch).to eq(2)
  end
end
