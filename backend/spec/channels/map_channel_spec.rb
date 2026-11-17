require "rails_helper"

RSpec.describe MapChannel, type: :channel do
  before do
    create_brand("infinitepay")
    create_brand("jim")
  end

  it "assina o canal de uma marca que o analista atende" do
    stub_connection current_user: create_analyst("Ana", brands: [ "infinitepay" ])

    subscribe(brand: "infinitepay")

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("map:infinitepay")
  end

  it "recusa marca que o analista não atende e marca que não existe" do
    stub_connection current_user: create_analyst("Ana", brands: [ "infinitepay" ])

    subscribe(brand: "jim")
    expect(subscription).to be_rejected

    subscribe(brand: "nenhuma")
    expect(subscription).to be_rejected
  end

  it "deixa a operação assinar qualquer marca" do
    stub_connection current_user: User.create!(name: "Olivia", role: "ops", token_digest: User.digest("t-olivia"))

    subscribe(brand: "jim")

    expect(subscription).to have_stream_from("map:jim")
  end
end

RSpec.describe ApplicationCable::Connection, type: :channel do
  before { create_brand }

  def protocols(token) = "actioncable-v1-json, helpdesk-token.#{Base64.urlsafe_encode64(token, padding: false)}"

  it "identifica a pessoa pelo token no subprotocolo, nunca pela URL" do
    ana = create_analyst("Ana")

    connect "/cable", headers: { "Sec-WebSocket-Protocol" => protocols(analyst_token("Ana")) }

    expect(connection.current_user).to eq(ana)
  end

  it "recusa conexão sem token válido ou de quem não é pessoa da operação" do
    expect { connect "/cable" }.to have_rejected_connection
    expect { connect "/cable", headers: { "Sec-WebSocket-Protocol" => protocols("errado") } }.to have_rejected_connection

    create_bot
    expect {
      connect "/cable", headers: { "Sec-WebSocket-Protocol" => protocols(DomainHelpers::BOT_TOKEN) }
    }.to have_rejected_connection
  end
end
