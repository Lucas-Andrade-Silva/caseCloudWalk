# Traces OpenTelemetry (ADR 0002, D13; ADR 0008, O2).
#
# O SDK lê o ambiente: OTEL_TRACES_EXPORTER (none por padrão no Compose, otlp com a pilha de observabilidade),
# OTEL_EXPORTER_OTLP_ENDPOINT e a amostragem (OTEL_TRACES_SAMPLER e _ARG). Nos testes, spec/support/tracing.rb
# configura um exportador em memória.
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/rails"
require "opentelemetry/instrumentation/pg"
require "opentelemetry/instrumentation/net/http"
require "opentelemetry/instrumentation/sidekiq"

unless Rails.env.test?
  OpenTelemetry::SDK.configure do |config|
    config.service_name = ENV.fetch("OTEL_SERVICE_NAME", "helpdesk-api")
    # Nesta versão, a instrumentação Rails não liga mais as dependências sozinha: sem pedir Rack e
    # ActionPack, nenhuma requisição HTTP vira span (visto na pilha real em 2026-11-18).
    config.use "OpenTelemetry::Instrumentation::Rack"
    config.use "OpenTelemetry::Instrumentation::ActionPack"
    config.use "OpenTelemetry::Instrumentation::ActiveRecord"
    config.use "OpenTelemetry::Instrumentation::PG", db_statement: :obfuscate
    config.use "OpenTelemetry::Instrumentation::Net::HTTP"
    config.use "OpenTelemetry::Instrumentation::Sidekiq"
  end
end
