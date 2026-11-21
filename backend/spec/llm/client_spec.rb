require "rails_helper"

RSpec.describe Llm::Client do
  let(:replay_dir) { Pathname(Dir.mktmpdir) }
  let(:valid) { { "category" => "maquininha", "language" => "pt", "frustration" => "alta", "confidence" => 0.9 } }
  let(:requests) { [] }

  after { FileUtils.rm_rf(replay_dir) }

  def groq_answer(content) = { "choices" => [ { "message" => { "content" => content } } ] }

  def live_client(answer = groq_answer(valid.to_json), **options)
    transport = lambda do |body|
      requests << body
      answer.is_a?(Exception) ? raise(answer) : answer
    end
    described_class.new(mode: "live", transport: transport, replay_dir: replay_dir, api_key: "chave-de-teste", **options)
  end

  it "no modo live, manda o texto redigido entre delimitadores e pede saída no schema estrito" do
    result = live_client.call(task: "enrich", input: "minha maquininha não liga, CPF 529.982.247-25")

    expect(result).to have_attributes(ok: true, data: valid, source: "live", prompt_version: "enrich-v1",
                                      model: "openai/gpt-oss-120b")
    body = requests.sole
    expect(body["model"]).to eq("openai/gpt-oss-120b")
    expect(body["temperature"]).to eq(0)
    expect(body.dig("response_format", "type")).to eq("json_schema")
    expect(body.dig("response_format", "json_schema", "strict")).to be(true)
    user = body["messages"].find { |message| message["role"] == "user" }["content"]
    expect(user).to eq("<mensagem>\nminha maquininha não liga, CPF [CPF]\n</mensagem>")
    expect(body.to_json).not_to include("529.982.247-25")
  end

  it "recusa resposta fora do schema ou que não é JSON" do
    off_schema = live_client(groq_answer(valid.merge("category" => "inventada").to_json))
    not_json = live_client(groq_answer("não sei"))

    expect(off_schema.call(task: "enrich", input: "oi")).to have_attributes(ok: false, error: "invalid_output")
    expect(not_json.call(task: "enrich", input: "oi")).to have_attributes(ok: false, error: "invalid_output")
  end

  it "abre o disjuntor depois de falhas seguidas e para de chamar por um tempo" do
    client = live_client(Net::ReadTimeout.new, breaker: Llm::CircuitBreaker.new(threshold: 3, cooldown: 30))

    3.times { expect(client.call(task: "enrich", input: "oi")).to have_attributes(ok: false, error: "Net::ReadTimeout") }
    expect(client.call(task: "enrich", input: "oi")).to have_attributes(ok: false, error: "circuit_open")
    expect(requests.size).to eq(3)
  end

  it "grava a resposta ao vivo quando pedido, e o replay devolve a mesma resposta sem chamar ninguém" do
    live_client(record: true).call(task: "enrich", input: "minha maquininha não liga")

    replay = described_class.new(mode: "replay", replay_dir: replay_dir)
    result = replay.call(task: "enrich", input: "minha maquininha não liga")

    expect(result).to have_attributes(ok: true, data: valid, source: "replay")
    expect(replay.call(task: "enrich", input: "outra mensagem")).to have_attributes(ok: false, error: "replay_miss")
  end

  it "no modo stub, responde no schema sem rede, de forma determinística" do
    client = described_class.new(mode: "stub")

    first = client.call(task: "enrich", input: "quero um empréstimo")
    second = client.call(task: "enrich", input: "quero um empréstimo")

    expect(first).to have_attributes(ok: true, source: "stub")
    expect(first.data).to eq(second.data)
    expect(first.data.keys).to contain_exactly("category", "language", "frustration", "confidence")
  end

  it "no modo off, não chama nada" do
    expect(described_class.new(mode: "off").call(task: "enrich", input: "oi")).to have_attributes(ok: false, error: "disabled")
  end
end
