require "spec_helper"

RSpec.describe Broker::ReplyPipeline do
  let(:now) { Time.utc(2026, 11, 16, 12, 0, 0) }
  let(:produced) { [] }
  let(:producer) do
    sink = produced
    Object.new.tap { |fake| fake.define_singleton_method(:produce_sync) { |message| sink << message } }
  end

  # Encaminhador falso: devolve o resultado ou levanta o erro configurado.
  def forwarder(outcome)
    Object.new.tap do |fake|
      fake.define_singleton_method(:forward) do |_body|
        raise outcome if outcome.is_a?(Exception) || (outcome.is_a?(Class) && outcome <= Exception)

        outcome
      end
    end
  end

  def pipeline(outcome) = described_class.new(forwarder: forwarder(outcome), producer: producer, logger: Logger.new(IO::NULL))

  def message(topic: "agent.replies", timestamp: now, headers: {})
    Broker::ReplyPipeline::Envelope.new(topic: topic, key: "ticket-1", raw_payload: '{"a":1}',
                                        headers: headers, timestamp: timestamp)
  end

  it "confirma a resposta entregue ou recusada de vez" do
    expect(pipeline(:delivered).handle(message, now: now)).to eq(Broker::ReplyPipeline::Action.ack)
    expect(pipeline(:rejected).handle(message, now: now)).to eq(Broker::ReplyPipeline::Action.ack)
    expect(produced).to be_empty
  end

  it "pausa e repete a mesma mensagem, sem gastar tentativa, quando a plataforma está fora" do
    [ Broker::ReplyForwarder::PlatformUnavailable.new("503"), Errno::ECONNREFUSED.new, Net::OpenTimeout.new ].each do |error|
      action = pipeline(error).handle(message, now: now)

      expect(action).to eq(Broker::ReplyPipeline::Action.pause(described_class::UNAVAILABLE_PAUSE))
    end
    expect(produced).to be_empty
  end

  it "manda a falha para o próximo estágio com tentativa, erro e tópico de origem" do
    action = pipeline(Broker::ReplyForwarder::RetryableError.new("plataforma respondeu 500"))
      .handle(message(headers: { "brand_id" => "jim" }), now: now)

    expect(action).to eq(Broker::ReplyPipeline::Action.ack)
    expect(produced).to eq([ {
      topic: "agent.replies.retry-1", key: "ticket-1", payload: '{"a":1}',
      headers: { "brand_id" => "jim", "x-attempt" => "1", "x-error" => "Broker::ReplyForwarder::RetryableError: plataforma respondeu 500",
                 "x-original-topic" => "agent.replies" }
    } ])
  end

  it "percorre retry-1, retry-2 e DLQ" do
    failing = pipeline(RuntimeError.new("bug"))
    retry1 = message(topic: "agent.replies.retry-1", timestamp: now - 10, headers: { "x-attempt" => "1",
                                                                                   "x-original-topic" => "agent.replies" })
    retry2 = message(topic: "agent.replies.retry-2", timestamp: now - 60, headers: { "x-attempt" => "2",
                                                                                   "x-original-topic" => "agent.replies" })

    failing.handle(retry1, now: now)
    failing.handle(retry2, now: now)

    expect(produced.map { |m| [ m[:topic], m[:headers]["x-attempt"], m[:headers]["x-original-topic"] ] }).to eq(
      [ [ "agent.replies.retry-2", "2", "agent.replies" ], [ "agent.replies.dlq", "3", "agent.replies" ] ]
    )
  end

  it "espera o tempo do estágio de retry antes de tentar" do
    early = message(topic: "agent.replies.retry-1", timestamp: now - 4)
    late = message(topic: "agent.replies.retry-2", timestamp: now - 15)

    expect(pipeline(:delivered).handle(early, now: now)).to eq(Broker::ReplyPipeline::Action.pause(6))
    expect(pipeline(:delivered).handle(late, now: now)).to eq(Broker::ReplyPipeline::Action.pause(45))
    expect(pipeline(:delivered).handle(message(topic: "agent.replies.retry-1", timestamp: now - 10), now: now))
      .to eq(Broker::ReplyPipeline::Action.ack)
  end
end
