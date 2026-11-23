require "prometheus/middleware/collector"
require "prometheus/middleware/exporter"

module Broker
  # Aplicação HTTP do broker: o webhook com as métricas RED na frente e o /metrics para o Prometheus
  # (ADR 0008, O3). Sem autenticação: só na rede do Compose.
  def self.rack_app(webhook_app)
    Rack::Builder.new do
      use Prometheus::Middleware::Collector
      use Prometheus::Middleware::Exporter
      run webhook_app
    end.to_app
  end
end
