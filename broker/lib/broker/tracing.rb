require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

module Broker
  # Traces do broker (ADR 0008, O2). O contexto W3C chega no webhook (header HTTP traceparent), segue nos
  # headers do Kafka e volta à plataforma no header HTTP da resposta do agente. Propagação explícita: a
  # instrumentação automática do rdkafka não reconhece a variante karafka-rdkafka.
  #
  # O SDK lê o ambiente (OTEL_TRACES_EXPORTER, OTEL_EXPORTER_OTLP_ENDPOINT, amostragem). Nos testes, os spans
  # ficam em memória.
  module Tracing
    TEST_EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new

    module_function

    def configure!
      OpenTelemetry::SDK.configure do |config|
        config.service_name = ENV.fetch("OTEL_SERVICE_NAME", "helpdesk-broker")
        if ENV["KARAFKA_ENV"] == "test"
          config.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(TEST_EXPORTER))
        end
      end
    end

    def tracer = OpenTelemetry.tracer_provider.tracer("helpdesk.broker")

    def from_rack(env)
      OpenTelemetry.propagation.extract(env, getter: OpenTelemetry::Common::Propagation.rack_env_getter)
    end

    def from_headers(headers) = OpenTelemetry.propagation.extract(headers || {})

    # Headers com o contexto do span atual (traceparent), sem perder os que já existiam.
    def with_context(headers)
      carrier = {}
      OpenTelemetry.propagation.inject(carrier)
      headers.merge(carrier)
    end
  end
end
