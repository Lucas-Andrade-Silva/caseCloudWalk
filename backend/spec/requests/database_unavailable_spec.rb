require "rails_helper"

# Banco fora do ar é falha da plataforma inteira, não da mensagem: responde 503, para o canal reenviar e o
# broker pausar em vez de mandar cada resposta para o retry e a DLQ (spec 05).
RSpec.describe "Plataforma com o banco fora do ar" do
  before do
    create_brand
    create_bot
  end

  [ ActiveRecord::ConnectionNotEstablished, ActiveRecord::DatabaseConnectionError, ActiveRecord::ConnectionTimeoutError ]
    .each do |error|
      it "responde 503 ao canal e ao agente quando acontece #{error.name}" do
        allow(Ingestion::ReceiveMessage).to receive(:call).and_raise(error)
        allow(User).to receive(:find_by_token).and_raise(error)

        post_channel
        expect(response).to have_http_status(:service_unavailable)
        expect(response.headers["Retry-After"]).to eq("5")

        post "/api/agent/replies", params: "{}", headers: { "Authorization" => "Bearer x", "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:service_unavailable)
      end
    end
end
