require "spec_helper"

RSpec.describe Broker::PlatformClient do
  it "chama a API do agente na plataforma com o token do bot" do
    requests = []
    transport = lambda do |uri, headers, body|
      requests << { uri: uri.to_s, headers: headers, body: body }
      201
    end
    client = described_class.new(base_url: "http://api:3000", token: "token-do-bot", transport: transport)

    expect(client.post_reply('{"a":1}')).to eq(201)
    expect(requests).to eq([
      { uri: "http://api:3000/api/agent/replies", body: '{"a":1}',
        headers: { "Content-Type" => "application/json", "Authorization" => "Bearer token-do-bot" } }
    ])
  end
end
