# Fechamento automático dos tickets resolvidos pela IA (ADR 0009, W4). Agendado em config/schedule.yml.
class AutoCloseAiTicketsJob
  include Sidekiq::Job

  # Uma execução perdida é coberta pela próxima, um minuto depois.
  sidekiq_options retry: false

  def perform
    Tickets::AutoClose.new.run
  end
end
