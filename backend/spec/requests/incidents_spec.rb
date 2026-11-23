require "rails_helper"

RSpec.describe "Incidentes" do
  let(:brand) { Brand.find_by!(slug: "infinitepay") }

  before do
    create_brand
    create_brand("jim")
    create_analyst("Ana")
    create_analyst("Bruno")
  end

  def incident_of(tickets)
    tickets.each { |ticket| ticket.update!(llm_facts: { "category" => "maquininha" }) }
    Incidents::Detect.call(tickets.last)
  end

  def json_as(name) = auth_as(name).merge("CONTENT_TYPE" => "application/json")

  def ai_ticket(customer)
    receive_message(provider_message_id: "wamid.#{customer}", customer_external_id: customer).ticket
  end

  def assigned_to(customer, name)
    ticket = escalated_ticket(customer)
    ticket.with_lock { Handoff::Assign.call(ticket: ticket, analyst: User.find_by!(name: name), trigger: "teste") }
    ticket
  end

  it "lista os incidentes abertos das marcas do analista, com contagem de tickets" do
    incident = incident_of(Array.new(5) { |index| ai_ticket("c-#{index}") })

    get "/api/incidents", headers: auth_as("Ana")

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["incidents"].sole).to include("id" => incident.id, "key" => "categoria:maquininha", "brand" => "infinitepay",
                                              "title" => incident.title, "draft_reply" => incident.draft_reply,
                                              "open_tickets" => 5)
  end

  it "não mostra incidente de marca que o analista não atende" do
    jim = Array.new(5) do |index|
      receive_message(provider_message_id: "wamid.j#{index}", customer_external_id: "j-#{index}", brand_slug: "jim").ticket
    end
    incident_of(jim)

    get "/api/incidents", headers: auth_as("Ana")

    expect(response.parsed_body["incidents"]).to eq([])
  end

  it "responder a todos: assume, responde e fecha cada ticket livre; o de outro analista fica de fora" do
    with_ai = ai_ticket("c-ai")
    waiting = escalated_ticket("c-espera")
    mine = assigned_to("c-meu", "Ana")
    others = assigned_to("c-bruno", "Bruno")
    extra = ai_ticket("c-extra")
    incident = incident_of([ with_ai, waiting, mine, others, extra ])

    post "/api/incidents/#{incident.id}/resolve", headers: json_as("Ana"),
                                                   params: { text: "Normalizou, pode testar de novo.", resolution_code: "resolved" }.to_json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("closed" => 4, "skipped" => [ { "id" => others.id, "reason" => "other_analyst" } ])
    [ with_ai, waiting, mine, extra ].each do |ticket|
      ticket.reload
      expect(ticket).to have_attributes(mode: "closed", resolution_code: "resolved", assignee_id: User.find_by!(name: "Ana").id)
      expect(ticket.messages.where(sender: "analyst").last.body).to eq("Normalizou, pode testar de novo.")
      expect(ticket.closing_summary).to be_present
    end
    expect(others.reload.mode).to eq("human")
    expect(incident.reload).to have_attributes(status: "resolved", resolved_by_id: User.find_by!(name: "Ana").id)
  end

  it "recusa responder sem texto ou com resolução inválida" do
    incident = incident_of(Array.new(5) { |index| ai_ticket("c-#{index}") })

    post "/api/incidents/#{incident.id}/resolve", headers: json_as("Ana"), params: { text: " " }.to_json
    expect(response).to have_http_status(:unprocessable_content)

    post "/api/incidents/#{incident.id}/resolve", headers: json_as("Ana"),
                                                   params: { text: "ok", resolution_code: "inventado" }.to_json
    expect(response).to have_http_status(:unprocessable_content)
    expect(incident.reload.status).to eq("open")
  end

  it "incidente já resolvido responde 409" do
    incident = incident_of(Array.new(5) { |index| ai_ticket("c-#{index}") })
    incident.update!(status: "resolved", resolved_at: Time.current)

    post "/api/incidents/#{incident.id}/resolve", headers: json_as("Ana"), params: { text: "ok" }.to_json

    expect(response).to have_http_status(:conflict)
  end
end
