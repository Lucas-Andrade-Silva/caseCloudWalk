require "spec_helper"

RSpec.describe Broker::ReplyForwarder do
  let(:log) { StringIO.new }
  let(:calls) { [] }

  def forwarder(status)
    client = Object.new
    calls_ref = calls
    client.define_singleton_method(:post_reply) do |body|
      calls_ref << body
      raise status if status.is_a?(Exception)

      status
    end
    described_class.new(client: client, logger: Logger.new(log))
  end

  it "entrega a resposta à plataforma sem alterar o corpo" do
    expect(forwarder(201).forward('{"agent_turn_id":"x"}')).to eq(:delivered)
    expect(calls).to eq([ '{"agent_turn_id":"x"}' ])
  end

  it "trata a duplicata (200) como entregue" do
    expect(forwarder(200).forward("{}")).to eq(:delivered)
  end

  it "encerra, com aviso no log, quando a plataforma recusa de forma definitiva (ticket sumiu ou já saiu da IA)" do
    [ 404, 409 ].each do |status|
      expect(forwarder(status).forward("{}")).to eq(:rejected)
    end
    expect(log.string).to include("404", "409")
  end

  # Decisão do dono (2026-11-24, cenário S4): resposta que a plataforma recusa como inválida é veneno e vai para a
  # DLQ, onde a operação a enxerga. Repetir não ajuda, então não passa pelas retentativas.
  it "marca como inválida a resposta que a plataforma recusa com 422" do
    expect(forwarder(422).forward("{}")).to eq(:invalid)
  end

  it "levanta erro quando a plataforma falha, para o Kafka reentregar" do
    [ 500, 503, 401, 403 ].each do |status|
      expect { forwarder(status).forward("{}") }.to raise_error(Broker::ReplyForwarder::RetryableError, /#{status}/)
    end
  end

  it "deixa o erro de rede subir, para o Kafka reentregar" do
    expect { forwarder(Errno::ECONNREFUSED.new).forward("{}") }.to raise_error(Errno::ECONNREFUSED)
  end
end
