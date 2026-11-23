require "opentelemetry/sdk"

# Traces nos testes: o SDK grava os spans em memória, sem rede (ADR 0008, O2). Em desenvolvimento e produção,
# config/initializers/opentelemetry.rb configura o exportador real.
module TracingHelpers
  EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new

  def finished_spans = EXPORTER.finished_spans

  def tracer = OpenTelemetry.tracer_provider.tracer("helpdesk-test")

  def trace_id_from(traceparent) = traceparent.to_s.split("-")[1]

  def hex_trace_id(span) = span.context.hex_trace_id
end

OpenTelemetry::SDK.configure do |config|
  config.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(TracingHelpers::EXPORTER))
end

RSpec.configure do |config|
  config.include TracingHelpers
  config.before { TracingHelpers::EXPORTER.reset }
end
