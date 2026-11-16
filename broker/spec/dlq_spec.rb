require "spec_helper"
require_relative "../karafka"

# Kafka real: a rotina da DLQ lista, republica e purga o que ainda não foi tratado.
RSpec.describe Broker::Dlq do
  let(:suffix) { SecureRandom.hex(4) }
  let(:dlq_topic) { "test.dlq.#{suffix}" }
  let(:main_topic) { "test.main.#{suffix}" }
  let(:dlq) do
    described_class.new(topic: dlq_topic, group: "test_dlq_admin_#{suffix}", logger: Logger.new(IO::NULL))
  end

  before do
    [ dlq_topic, main_topic ].each { |name| Karafka::Admin.create_topic(name, 1, 1) }
  end

  after do
    [ dlq_topic, main_topic ].each { |name| Karafka::Admin.delete_topic(name) }
  end

  def dead_letter(n)
    Karafka.producer.produce_sync(
      topic: dlq_topic, key: "ticket-#{n}", payload: %({"n":#{n}}),
      headers: { "brand_id" => "jim", "x-attempt" => "3", "x-error" => "bug", "x-original-topic" => main_topic }
    )
  end

  it "lista o que não foi tratado, republica no tópico de origem sem os headers de controle e esvazia" do
    dead_letter(1)
    dead_letter(2)

    listed = dlq.list
    expect(listed.map { |entry| [ entry[:key], entry[:error], entry[:original_topic] ] }).to eq(
      [ [ "ticket-1", "bug", main_topic ], [ "ticket-2", "bug", main_topic ] ]
    )

    expect(dlq.replay).to eq(2)

    replayed = Karafka::Admin.read_topic(main_topic, 0, 10)
    expect(replayed.map(&:raw_payload)).to eq([ '{"n":1}', '{"n":2}' ])
    expect(replayed.map(&:key)).to eq(%w[ticket-1 ticket-2])
    expect(replayed.first.headers).to eq("brand_id" => "jim")
    expect(dlq.list).to be_empty
  end

  it "purga sem republicar, e só o que chegou depois volta a aparecer" do
    dead_letter(1)

    expect(dlq.purge).to eq(1)
    expect(dlq.list).to be_empty

    dead_letter(2)
    expect(dlq.list.map { |entry| entry[:key] }).to eq(%w[ticket-2])
    expect(Karafka::Admin.read_topic(main_topic, 0, 10)).to be_empty
  end
end
