require "rails_helper"

RSpec.describe "GET /api/me" do
  before do
    create_brand("infinitepay")
    create_brand("jim")
  end

  it "diz quem é o analista e quais marcas ele atende" do
    analyst = create_analyst("Ana", brands: %w[infinitepay jim])

    get "/api/me", headers: auth_as("Ana")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "id" => analyst.id, "name" => "Ana", "role" => "analyst", "brands" => %w[infinitepay jim]
    )
  end

  it "atende a operação, que não é presa a uma marca" do
    User.create!(name: "Olivia", role: "ops", token_digest: User.digest("token-de-olivia"))

    get "/api/me", headers: { "Authorization" => "Bearer token-de-olivia" }

    expect(response.parsed_body).to include("name" => "Olivia", "role" => "ops", "brands" => [])
  end

  it "recusa token inválido e o bot" do
    create_bot

    get "/api/me", headers: { "Authorization" => "Bearer nada" }
    expect(response).to have_http_status(:unauthorized)

    get "/api/me", headers: { "Authorization" => "Bearer #{DomainHelpers::BOT_TOKEN}" }
    expect(response).to have_http_status(:forbidden)
  end
end
