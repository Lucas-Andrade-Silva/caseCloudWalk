# Configuração das integrações, lida do ambiente (ver compose.yaml e .env.example).
# Listas de segredos permitem rotação: o receptor aceita todos; o emissor assina com o primeiro.
module IntegrationConfig
  module_function

  def channel_webhook_secrets = list("CHANNEL_WEBHOOK_SECRETS")
  def broker_webhook_secret = list("BROKER_WEBHOOK_SECRETS").first
  def broker_webhook_url = ENV.fetch("BROKER_WEBHOOK_URL")

  def list(name)
    ENV.fetch(name, "").split(",").map(&:strip).reject(&:empty?)
  end
end
