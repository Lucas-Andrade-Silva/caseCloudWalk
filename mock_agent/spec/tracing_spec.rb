require "spec_helper"

# O trace atravessa o agente simulado (ADR 0008, O2): a resposta leva o contexto da mensagem que a originou,
# mesmo quando o caos adia a publicação.
RSpec.describe MockAgent::Tracing do
  let(:trace_id) { "4bf92f3577b34da6a3ce929d0e0e4736" }
  let(:parent_span_id) { "00f067aa0ba902b7" }

  before { described_class::TEST_EXPORTER.reset }

  it "responde dentro de um span filho da mensagem e devolve os headers da resposta com esse contexto" do
    reply_headers = described_class.within_message("traceparent" => "00-#{trace_id}-#{parent_span_id}-01") { |headers| headers }

    span = described_class::TEST_EXPORTER.finished_spans.find { |finished| finished.name == "agent respond" }
    expect(span.hex_trace_id).to eq(trace_id)
    expect(span.hex_parent_span_id).to eq(parent_span_id)
    expect(span.kind).to eq(:consumer)
    expect(reply_headers).to eq("traceparent" => "00-#{trace_id}-#{span.hex_span_id}-01")
  end

  it "sem contexto na mensagem, começa um trace novo" do
    reply_headers = described_class.within_message({}) { |headers| headers }

    expect(reply_headers["traceparent"]).to match(/\A00-\h{32}-\h{16}-01\z/)
  end
end
