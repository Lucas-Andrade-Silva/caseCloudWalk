require "rails_helper"

RSpec.describe "GET /api/map" do
  before do
    create_brand("infinitepay")
    create_brand("jim")
    create_analyst("Ana", brands: [ "infinitepay" ])
    User.create!(name: "Olivia", role: "ops", token_digest: User.digest("token-de-olivia"))
  end

  def ids = response.parsed_body["tickets"].map { |ticket| ticket["id"] }

  it "mostra os tickets abertos das marcas do analista, com o cluster de cada um" do
    tagged = receive_message(provider_message_id: "w1", customer_external_id: "c1").ticket
    tagged.update!(tags: %w[alto_valor recontato], priority: "p1")
    queued = escalated_ticket("c2")
    plain = receive_message(provider_message_id: "w3", customer_external_id: "c3").ticket
    closed = receive_message(provider_message_id: "w4", customer_external_id: "c4").ticket
    closed.update!(mode: "closed", closed_at: Time.current, resolution_code: "resolved")
    receive_message(provider_message_id: "w5", brand_slug: "jim", customer_external_id: "c5")

    get "/api/map", headers: auth_as("Ana")

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("total" => 3, "limit" => 500)
    expect(ids.first).to eq(tagged.id)
    expect(ids).to contain_exactly(tagged.id, queued.id, plain.id)

    by_id = body["tickets"].index_by { |ticket| ticket["id"] }
    expect(by_id[tagged.id]).to include("brand" => "infinitepay", "mode" => "ai", "priority" => "p1",
                                        "cluster" => { "key" => "tag:alto_valor", "label" => "alto_valor" })
    expect(by_id[queued.id]["cluster"]).to eq("key" => "fila:infinitepay-atendimento", "label" => "infinitepay-atendimento")
    expect(by_id[plain.id]["cluster"]).to eq("key" => "marca:infinitepay", "label" => "Infinitepay sem fila")
    expect(by_id[queued.id]).to include("mode" => "pending_human")
    expect(by_id[queued.id]["first_response_due_at"]).to be_present
  end

  it "mostra todas as marcas para a operação e recusa quem não é pessoa da operação" do
    receive_message(provider_message_id: "w1", customer_external_id: "c1")
    receive_message(provider_message_id: "w2", brand_slug: "jim", customer_external_id: "c2")

    get "/api/map", headers: { "Authorization" => "Bearer token-de-olivia" }
    expect(response.parsed_body["total"]).to eq(2)

    create_bot
    get "/api/map", headers: { "Authorization" => "Bearer #{DomainHelpers::BOT_TOKEN}" }
    expect(response).to have_http_status(:forbidden)
  end
end
