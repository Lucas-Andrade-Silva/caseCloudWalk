# Job periódico do vigia do agente. O agendamento está em config/schedule.yml (sidekiq-cron).
class AgentSilenceWatchdogJob
  include Sidekiq::Job

  # Uma execução perdida é coberta pela próxima, 5 s depois; repetir não ajuda.
  sidekiq_options retry: false

  def perform
    timeout = Integer(ENV.fetch("AGENT_SILENCE_TIMEOUT_SECONDS", "30"))
    Handoff::AgentSilenceWatchdog.new(timeout: timeout).run
  end
end
