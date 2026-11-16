# Apoio para criar dados de domínio e assinar webhooks nos testes.
module DomainHelpers
  CHANNEL_SECRET = "segredo-do-canal".freeze
  BOT_TOKEN = "token-do-bot".freeze

  def create_brand(slug = "infinitepay")
    Brand.create!(slug: slug, name: slug.capitalize)
  end

  def create_bot(token: BOT_TOKEN)
    User.create!(name: "Agente de IA", role: "bot", token_digest: User.digest(token))
  end

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

  def delete_domain_data
    [ OutboxEvent, ProcessedEvent, ConversationEvent, Message, InboundEvent, Ticket, Customer, User, Brand ]
      .each(&:delete_all)
  end
end

RSpec.configure do |config|
  config.include DomainHelpers

  # A suíte parte de um banco vazio, mesmo que uma execução anterior tenha sido interrompida no
  # meio de um teste sem transação.
  config.before(:suite) { Object.new.extend(DomainHelpers).delete_domain_data }

  config.before do
    allow(IntegrationConfig).to receive(:channel_webhook_secrets).and_return([ DomainHelpers::CHANNEL_SECRET ])
  end
end
