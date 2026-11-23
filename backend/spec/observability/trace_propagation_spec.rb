require "rails_helper"

RSpec.describe "Propagação do trace pelo outbox" do
  before { create_brand }

  it "o evento do outbox guarda o contexto do trace de quem o criou" do
    span_trace = nil
    tracer.in_span("entrada") do |span|
      span_trace = hex_trace_id(span)
      receive_message
    end

    expect(trace_id_from(OutboxEvent.sole.headers["traceparent"])).to eq(span_trace)
  end

  it "sem trace ativo, o evento não leva contexto" do
    receive_message

    expect(OutboxEvent.sole.headers).not_to have_key("traceparent")
  end

  it "o relay continua o trace ao entregar: o webhook sai com o contexto do span de entrega" do
    span_trace = nil
    tracer.in_span("entrada") do |span|
      span_trace = hex_trace_id(span)
      receive_message
    end
    sent = []
    producer = Object.new
    producer.define_singleton_method(:produce_sync) { |message| sent << message }

    Outbox::Relay.new(producer: producer).publish_pending

    delivery = finished_spans.find { |span| span.name == "outbox deliver" }
    expect(delivery).to be_present
    expect(delivery.hex_trace_id).to eq(span_trace)
    expect(delivery.kind).to eq(:producer)
    expect(trace_id_from(sent.sole[:headers]["traceparent"])).to eq(span_trace)
    expect(sent.sole[:headers]["traceparent"].split("-")[2]).to eq(delivery.hex_span_id)
  end
end
