require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

module MockAgent
  # Traces do agente simulado (ADR 0008, O2): continua o trace que chega nos headers do Kafka e o passa
  # adiante nos headers da resposta. Propagação explícita: a instrumentação automática do rdkafka não
  # reconhece a variante karafka-rdkafka.
  module Tracing
    TEST_EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new

    module_function

    def configure!
      OpenTelemetry::SDK.configure do |config|
        config.service_name = ENV.fetch("OTEL_SERVICE_NAME", "helpdesk-mock-agent")
        if ENV["KARAFKA_ENV"] == "test"
          config.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(TEST_EXPORTER))
        end
      end
    end

    def tracer = OpenTelemetry.tracer_provider.tracer("helpdesk.mock_agent")

    # Executa o bloco num span filho da mensagem e entrega a ele os headers que a resposta deve levar. Os
    # headers são calculados agora: com o caos de latência, a resposta sai depois e o contexto vai junto.
    def within_message(headers)
      parent = OpenTelemetry.propagation.extract(headers || {})
      OpenTelemetry::Context.with_current(parent) do
        tracer.in_span("agent respond", kind: :consumer, attributes: { "messaging.system" => "kafka" }) do
          carrier = {}
          OpenTelemetry.propagation.inject(carrier)
          yield carrier
        end
      end
    end
  end
end
