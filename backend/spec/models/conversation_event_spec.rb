require "rails_helper"

RSpec.describe ConversationEvent do
  it "é append-only: não aceita alteração nem exclusão pelo modelo" do
    create_brand
    event = receive_message.ticket.conversation_events.first

    expect { event.update!(kind: "outra.coisa") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(event.reload.kind).to eq("ticket.opened")
  end
end
