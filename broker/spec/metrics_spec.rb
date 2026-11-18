require "spec_helper"

# Métricas RED do broker para o Prometheus (ADR 0008, O3).
RSpec.describe "Métricas do broker" do
  it "expõe em /metrics as requisições do broker por rota e código" do
    inner = ->(_env) { [ 204, {}, [] ] }
    app = Rack::MockRequest.new(Broker.rack_app(inner))

    app.post("/webhooks/helpdesk")
    response = app.get("/metrics")

    expect(response.status).to eq(200)
    expect(response.body).to match(%r{^http_server_requests_total\{code="204",method="post",path="/webhooks/helpdesk"\} \d+\.0$})
  end
end
