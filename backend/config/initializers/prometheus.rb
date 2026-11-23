# Métricas Prometheus (ADR 0002, D13; ADR 0008, O3 e O5).
#
# - Collector: RED por rota (requisições, erros, duração), com UUIDs e números colapsados no caminho.
# - Atualizador: medidas do domínio lidas do banco a cada coleta (Observability::DomainMetrics).
# - Exporter: responde em /metrics, sem autenticação; em produção ficaria só na rede interna.
#
# Limitação: com vários processos Puma (WEB_CONCURRENCY > 1), os contadores RED são de cada processo. As
# medidas do domínio vêm do banco e valem para todos.
require "prometheus/middleware/collector"
require "prometheus/middleware/exporter"

# Definido aqui porque as classes de app/ ainda não carregam durante os inicializadores; a chamada a
# DomainMetrics só acontece na requisição.
domain_metrics_refresher = Class.new do
  def initialize(app) = @app = app

  def call(env)
    Observability::DomainMetrics.refresh! if env["PATH_INFO"] == "/metrics"
    @app.call(env)
  end
end

Rails.application.config.middleware.use Prometheus::Middleware::Collector
Rails.application.config.middleware.use domain_metrics_refresher
Rails.application.config.middleware.use Prometheus::Middleware::Exporter
