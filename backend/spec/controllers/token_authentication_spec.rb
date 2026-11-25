require "rails_helper"

# Autenticação por token Bearer, compartilhada pelas rotas da API (pessoas da operação, operação e bot).
RSpec.describe TokenAuthentication, type: :controller do
  controller(ApplicationController) do
    include TokenAuthentication

    authenticate_roles %w[analyst ops], forbidden: "apenas pessoas da operação"

    def index
      render json: { user_id: current_user.id }
    end
  end

  def bearer(token) = request.headers["Authorization"] = "Bearer #{token}"

  it "responde 401 sem token" do
    get :index

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "token inválido")
  end

  it "responde 401 com token desconhecido ou fora do formato Bearer" do
    request.headers["Authorization"] = "Token #{DomainHelpers::BOT_TOKEN}"
    create_bot
    get :index
    expect(response).to have_http_status(:unauthorized)

    bearer("nao-existe")
    get :index
    expect(response).to have_http_status(:unauthorized)
  end

  it "responde 403 com a mensagem da rota quando o papel não pode entrar" do
    create_bot
    bearer(DomainHelpers::BOT_TOKEN)

    get :index

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq("error" => "apenas pessoas da operação")
  end

  it "deixa passar o papel aceito e expõe current_user" do
    create_brand
    ana = create_analyst("Ana")
    bearer(analyst_token("Ana"))

    get :index

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["user_id"]).to eq(ana.id)
  end
end
