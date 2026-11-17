# Apoio para criar dados de domínio e assinar webhooks nos testes.
module DomainHelpers
  CHANNEL_SECRET = "segredo-do-canal".freeze
  BOT_TOKEN = "token-do-bot".freeze

  # Marca com a sua fila humana padrão (ADR 0004, H2), atendida por uma equipe da marca (ADR 0005, R1).
  def create_brand(slug = "infinitepay")
    brand = Brand.create!(slug: slug, name: slug.capitalize)
    team = Team.create!(slug: "#{slug}-equipe", name: "Equipe #{brand.name}")
    TicketQueue.create!(brand: brand, team: team, slug: "#{slug}-atendimento", name: "Atendimento #{brand.name}",
                        default: true)
    brand
  end

  def default_queue(slug = "infinitepay")
    TicketQueue.find_by!(slug: "#{slug}-atendimento")
  end

  def create_bot(token: BOT_TOKEN)
    User.create!(name: "Agente de IA", role: "bot", token_digest: User.digest(token))
  end

  def create_analyst(name, brands: [ "infinitepay" ])
    analyst = User.create!(name: name, role: "analyst", token_digest: User.digest(analyst_token(name)))
    brands.each { |slug| TeamMembership.create!(user: analyst, team: default_queue(slug).team) }
    analyst
  end

  def analyst_token(name) = "token-de-#{name.downcase}"

  def auth_as(name) = { "Authorization" => "Bearer #{analyst_token(name)}" }

  def signed_headers(body, secret: CHANNEL_SECRET, id: SecureRandom.uuid, timestamp: Time.now.to_i)
    {
      "CONTENT_TYPE" => "application/json",
      "X-Webhook-Id" => id,
      "X-Webhook-Timestamp" => timestamp.to_s,
      "X-Webhook-Signature" => Webhooks::Signature.sign(id: id, timestamp: timestamp, body: body, secret: secret)
    }
  end

  def channel_payload(overrides = {})
    {
      provider_message_id: "wamid.1",
      brand: "infinitepay",
      customer: { external_id: "cust-42", name: "Maria" },
      text: "minha maquininha não liga"
    }.deep_merge(overrides)
  end

  def post_channel(channel = "whatsapp", payload = channel_payload, **signing)
    body = payload.to_json
    post "/webhooks/channels/#{channel}", params: body, headers: signed_headers(body, **signing)
  end

  def receive_message(overrides = {})
    Ingestion::ReceiveMessage.call(
      **{
        channel: "whatsapp",
        provider_message_id: "wamid.1",
        brand_slug: "infinitepay",
        customer_external_id: "cust-42",
        customer_name: "Maria",
        text: "minha maquininha não liga"
      }.merge(overrides)
    )
  end

  # Abre um ticket de um cliente próprio e o escala, como o agente faria.
  def escalated_ticket(customer, brand: "infinitepay", priority: "p3")
    ticket = receive_message(provider_message_id: "wamid.#{customer}", customer_external_id: customer,
                             brand_slug: brand).ticket
    ticket.update!(priority: priority)
    ticket.with_lock do
      Handoff::Escalate.call(ticket: ticket, trigger: "agent_requested", reason: "teste", actor: "bot")
    end
    ticket.reload
  end

  def delete_domain_data
    [ OutboxEvent, ProcessedEvent, Decision, ClosingSummary, MemoryErasure, ConversationEvent, Message, InboundEvent, Ticket, RuleSet,
      TeamMembership, TicketQueue, Team, Customer, User, Brand, PriorityLevel ].each(&:delete_all)
  end
end

RSpec.configure do |config|
  config.include DomainHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  # A suíte parte de um banco vazio, mesmo que uma execução anterior tenha sido interrompida no
  # meio de um teste sem transação.
  config.before(:suite) { Object.new.extend(DomainHelpers).delete_domain_data }

  config.before do
    PriorityLevel.ensure_defaults!
    allow(IntegrationConfig).to receive(:channel_webhook_secrets).and_return([ DomainHelpers::CHANNEL_SECRET ])
  end
end
