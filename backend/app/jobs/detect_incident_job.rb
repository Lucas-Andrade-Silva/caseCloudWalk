# Detecção do Modo Incidente (ADR 0009, W2), depois da entrada e de cada enriquecimento. Sem nova tentativa: o
# próximo ticket parecido roda a detecção de novo.
class DetectIncidentJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    Incidents::Detect.call(ticket) if ticket
  end
end
