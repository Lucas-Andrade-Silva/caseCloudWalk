require "spec_helper"

# O trace atravessa o broker nos dois sentidos (ADR 0008, O2): webhook HTTP → Kafka e Kafka → API.
RSpec.describe "Propagação do trace no broker" do
  let(:trace_id) { "4bf92f3577b34da6a3ce929d0e0e4736" }
  let(:incoming) { "00-#{trace_id}-00f067aa0ba902b7-01" }

  before { Broker::Tracing::TEST_EXPORTER.reset }

  def spans = Broker::Tracing::TEST_EXPORTER.finished_spans

  it "o webhook que chega com contexto sai no Kafka com o mesmo trace, num span de publicação" do
    sent = []
    producer = Object.new
    producer.define_singleton_method(:produce_sync) { |message| sent << message }
    app = Broker::WebhookApp.new(producer: producer, secrets: [ "s" ], allowed_topics: [ "helpdesk.messages" ],
                                 logger: Logger.new(IO::NULL))
    body = { topic: "helpdesk.messages", key: "t1", headers: { "event_id" => "e1" }, payload: { "seq" => 1 } }.to_json
    timestamp = Time.now.to_i

    Rack::MockRequest.new(app).post(
      "/webhooks/helpdesk", input: body, "CONTENT_TYPE" => "application/json",
      "HTTP_TRACEPARENT" => incoming, "HTTP_X_WEBHOOK_ID" => "e1", "HTTP_X_WEBHOOK_TIMESTAMP" => timestamp.to_s,
      "HTTP_X_WEBHOOK_SIGNATURE" => Broker::Signature.sign(id: "e1", timestamp: timestamp, body: body, secret: "s")
    )

    publish = spans.find { |span| span.name == "kafka publish helpdesk.messages" }
    expect(publish.hex_trace_id).to eq(trace_id)
    expect(publish.kind).to eq(:producer)
    expect(sent.size).to eq(1)
    expect(sent.first[:headers]["traceparent"]).to eq("00-#{trace_id}-#{publish.hex_span_id}-01")
    expect(sent.first[:headers]["event_id"]).to eq("e1")
  end

  it "a resposta do agente é encaminhada à API dentro do trace que veio no Kafka" do
    seen = nil
    forwarder = Object.new
    forwarder.define_singleton_method(:forward) { |_raw| seen = OpenTelemetry::Trace.current_span.context.hex_trace_id }
    pipeline = Broker::ReplyPipeline.new(forwarder: forwarder, producer: Object.new, logger: Logger.new(IO::NULL),
                                         stages: Broker::ReplyPipeline.stages("agent.replies"))
    envelope = Broker::ReplyPipeline::Envelope.new(topic: "agent.replies", key: "t1", raw_payload: "{}",
                                                   headers: { "traceparent" => incoming }, timestamp: Time.now)

    pipeline.handle(envelope)

    expect(seen).to eq(trace_id)
    expect(spans.map(&:name)).to include("kafka consume agent.replies")
  end

  it "a chamada à API leva o contexto do span atual no header traceparent" do
    sent_headers = nil
    client = Broker::PlatformClient.new(base_url: "http://api:3000", token: "t",
                                        transport: ->(_uri, headers, _body) { sent_headers = headers and 201 })

    Broker::Tracing.tracer.in_span("teste") { |span| client.post_reply("{}") and (@span = span) }

    expect(sent_headers["traceparent"]).to eq("00-#{@span.context.hex_trace_id}-#{@span.context.hex_span_id}-01")
    expect(sent_headers["Authorization"]).to eq("Bearer t")
  end
end
