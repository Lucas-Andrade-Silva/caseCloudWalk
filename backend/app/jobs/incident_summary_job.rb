# Título e rascunho do incidente pela LLM (ADR 0009, W1). Sem nova tentativa: o template já está no incidente.
class IncidentSummaryJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(incident_id)
    incident = Incident.find_by(id: incident_id)
    Incidents::Summarize.call(incident) if incident&.open?
  end
end
