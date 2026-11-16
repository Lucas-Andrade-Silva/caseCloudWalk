# Sidekiq: só jobs (ADR 0002, D3). Nada que precise ser exato vive no Redis.
redis = { url: ENV.fetch("REDIS_URL", "redis://redis:6379/0") }

Sidekiq.configure_server { |config| config.redis = redis }
Sidekiq.configure_client { |config| config.redis = redis }

# O padrão do sidekiq-cron confere o agendamento a cada 30 s, o que tornaria inútil um job de 5 s.
Sidekiq::Cron.configure do |config|
  config.cron_poll_interval = 5
  config.cron_schedule_file = Rails.root.join("config/schedule.yml").to_s
end
