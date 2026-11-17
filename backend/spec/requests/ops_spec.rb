require "rails_helper"

RSpec.describe "API de operação" do
  let(:ops) { { "Authorization" => "Bearer token-de-olivia", "CONTENT_TYPE" => "application/json" } }
  let(:brand) { Brand.find_by!(slug: "infinitepay") }
  let(:catch_all) { { "id" => "todas", "name" => "Todas", "when" => {}, "then" => { "priority" => "p3" } } }
  let(:credit_rule) do
    { "id" => "credito", "name" => "Crédito",
      "when" => { "fact" => "message_text", "op" => "contains_any", "value" => [ "crédito" ] },
      "then" => { "queue" => "credito-infinitepay", "priority" => "p1" } }
  end

  before do
    create_brand
    create_brand("jim")
    User.create!(name: "Olivia", role: "ops", token_digest: User.digest("token-de-olivia"))
    create_analyst("Ana")
  end

  def call(method, path, body = nil, headers: ops)
    send(method, path, params: body&.to_json, headers: headers)
  end

  it "exige um usuário de operação" do
    call(:get, "/api/ops/teams", headers: {})
    expect(response).to have_http_status(:unauthorized)

    call(:get, "/api/ops/teams", headers: auth_as("Ana"))
    expect(response).to have_http_status(:forbidden)
  end

  it "cria equipe e fila; o analista da equipe passa a puxar os tickets da fila" do
    call(:post, "/api/ops/teams", { slug: "credito", name: "Crédito" })
    expect(response).to have_http_status(:created)
    team_id = response.parsed_body["id"]

    call(:post, "/api/ops/queues", { brand: "infinitepay", team_id: team_id, slug: "credito-infinitepay",
                                     name: "Crédito InfinitePay" })
    expect(response).to have_http_status(:created)

    beto = create_analyst("Beto", brands: [])
    call(:post, "/api/ops/teams/#{team_id}/members", { user_id: beto.id })
    expect(response).to have_http_status(:no_content)

    ticket = receive_message.ticket
    ticket.update!(queue: TicketQueue.find_by!(slug: "credito-infinitepay"))
    ticket.with_lock { Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: "x", actor: "bot") }

    post "/api/work/next", headers: auth_as("Beto")
    expect(response.parsed_body["id"]).to eq(ticket.id)

    call(:delete, "/api/ops/teams/#{team_id}/members/#{beto.id}")
    expect(response).to have_http_status(:no_content)
    expect(beto.reload.queues).to be_empty
  end

  it "recusa fila de equipe ou marca inexistente e slug repetido" do
    call(:post, "/api/ops/queues", { brand: "outra", team_id: default_queue.team_id, slug: "x", name: "X" })
    expect(response).to have_http_status(:unprocessable_content)

    call(:post, "/api/ops/queues", { brand: "infinitepay", team_id: default_queue.team_id,
                                     slug: "infinitepay-atendimento", name: "Repetida" })
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "edita nome e equipe de uma fila" do
    other = Team.create!(slug: "outra", name: "Outra")

    call(:patch, "/api/ops/queues/#{default_queue.id}", { name: "Atendimento geral", team_id: other.id })

    expect(response).to have_http_status(:ok)
    expect(default_queue.reload).to have_attributes(name: "Atendimento geral", team: other)
  end

  describe "regras" do
    before do
      TicketQueue.create!(brand: brand, team: default_queue.team, slug: "credito-infinitepay", name: "Crédito")
    end

    it "cria rascunho, edita, publica e lista as versões" do
      call(:post, "/api/ops/brands/infinitepay/rule_sets", { rules: [ catch_all ] })
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("version" => 1, "status" => "draft")
      id = response.parsed_body["id"]

      call(:patch, "/api/ops/rule_sets/#{id}", { rules: [ credit_rule, catch_all ] })
      expect(response).to have_http_status(:ok)

      call(:post, "/api/ops/rule_sets/#{id}/publish")
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "published")

      call(:patch, "/api/ops/rule_sets/#{id}", { rules: [ catch_all ] })
      expect(response).to have_http_status(:conflict)

      call(:post, "/api/ops/brands/infinitepay/rule_sets", { rules: [ catch_all ] })
      expect(response.parsed_body["version"]).to eq(2)

      call(:get, "/api/ops/brands/infinitepay/rule_sets")
      expect(response.parsed_body.map { |set| [ set["version"], set["status"] ] }).to eq([ [ 2, "draft" ], [ 1, "published" ] ])
    end

    it "devolve os erros de validação com caminho" do
      call(:post, "/api/ops/brands/infinitepay/rule_sets", { rules: [ credit_rule.merge("then" => { "queue" => "jim-atendimento" }) ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].map { |e| e["path"] }).to eq([ "rules[0].then.queue" ])
      expect(RuleSet.count).to eq(0)
    end

    it "mostra no dry-run o que mudaria nos últimos tickets, sem gravar nada" do
      RuleSet.create!(brand: brand, version: 1, rules: [ catch_all ]).publish!
      credit = receive_message(provider_message_id: "a", customer_external_id: "c-1", text: "meu crédito sumiu").ticket
      receive_message(provider_message_id: "b", customer_external_id: "c-2", text: "maquininha travou")
      call(:post, "/api/ops/brands/infinitepay/rule_sets", { rules: [ credit_rule, catch_all ] })
      decisions_before = Decision.count

      call(:post, "/api/ops/rule_sets/#{response.parsed_body['id']}/dry_run", { limit: 50 })

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("evaluated" => 2, "changed" => 1)
      change = body["changes"].sole
      expect(change).to include("ticket_id" => credit.id)
      expect(change["before"]).to include("rule_id" => "todas", "priority" => "p3", "queue" => nil)
      expect(change["after"]).to include("rule_id" => "credito", "priority" => "p1", "queue" => "credito-infinitepay")
      expect(Decision.count).to eq(decisions_before)
      expect(credit.reload.priority).to eq("p3")
    end
  end

  describe "apoio às telas" do
    it "lista os analistas com as equipes de cada um" do
      call(:get, "/api/ops/analysts")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([
        { "id" => User.find_by!(name: "Ana").id, "name" => "Ana", "teams" => [ "infinitepay-equipe" ] }
      ])
    end

    it "publica o catálogo de fatos e operadores das regras" do
      call(:get, "/api/ops/rules/catalog")

      expect(response.parsed_body["facts"]).to include("amount" => "number", "message_text" => "text")
      expect(response.parsed_body["operators"]).to include("number" => %w[eq gt gte lt lte], "text" => [ "contains_any" ])
    end

    it "exige a operação" do
      call(:get, "/api/ops/analysts", headers: auth_as("Ana"))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "exclusão da memória de um cliente" do
    def closed_ticket(brand_slug, provider_id)
      ticket = receive_message(brand_slug: brand_slug, provider_message_id: provider_id).ticket
      ticket.update!(mode: "closed", closed_at: Time.current, resolution_code: "resolved")
      ClosingSummary.create!(ticket: ticket, brand: ticket.brand, customer: ticket.customer, version: 1,
                             source: "template", text: "resumo", expires_at: 90.days.from_now)
      ticket
    end

    it "apaga os resumos, esquece os contatos anteriores e registra quem pediu, sem tocar na outra marca" do
      closed_ticket("infinitepay", "wamid.1")
      closed_ticket("infinitepay", "wamid.2")
      jim = closed_ticket("jim", "wamid.jim")
      travel 1.second

      call(:delete, "/api/ops/brands/infinitepay/customers/cust-42/memory")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("summaries_deleted" => 2)
      expect(ClosingSummary.pluck(:ticket_id)).to eq([ jim.id ])
      customer = Customer.find_by!(brand: brand, external_id: "cust-42")
      erasure = MemoryErasure.sole
      expect(erasure).to have_attributes(brand: brand, customer: customer, summaries_deleted: 2,
                                         requested_by: User.find_by!(name: "Olivia"))
      again = receive_message(provider_message_id: "wamid.3").ticket
      expect(Memory::Recall.call(ticket: again)[:tickets]).to eq([])
      expect(Memory::Recall.call(ticket: receive_message(brand_slug: "jim", provider_message_id: "wamid.jim2").ticket)[:tickets].size).to eq(1)
    end

    it "responde 404 para marca ou cliente desconhecido e exige a operação" do
      call(:delete, "/api/ops/brands/infinitepay/customers/ninguem/memory")
      expect(response).to have_http_status(:not_found)
      call(:delete, "/api/ops/brands/nenhuma/customers/cust-42/memory")
      expect(response).to have_http_status(:not_found)
      call(:delete, "/api/ops/brands/infinitepay/customers/cust-42/memory", headers: auth_as("Ana"))
      expect(response).to have_http_status(:forbidden)
      expect(MemoryErasure.count).to eq(0)
    end
  end
end
