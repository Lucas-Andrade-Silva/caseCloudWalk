require "rails_helper"

RSpec.describe "Mapa vivo: publicação das mudanças de ticket" do
  include ActionCable::TestHelper

  before { create_brand }

  it "publica o ticket no canal da marca quando ele muda" do
    expect { receive_message }.to have_broadcasted_to("map:infinitepay").with { |data|
      expect(data["type"]).to eq("ticket.upsert")
      expect(data["ticket"]).to include("brand" => "infinitepay", "mode" => "ai", "cluster" => include("key" => "marca:infinitepay"))
    }
  end

  it "avisa que o ticket saiu do mapa quando ele fecha" do
    ticket = receive_message.ticket

    expect {
      ticket.update!(mode: "closed", closed_at: Time.current, resolution_code: "resolved")
    }.to have_broadcasted_to("map:infinitepay").with("type" => "ticket.removed", "id" => ticket.id)
  end
end
