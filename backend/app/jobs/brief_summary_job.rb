# Brief do handoff por LLM (ADR 0008). Sem nova tentativa: o template já está no ticket.
class BriefSummaryJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    Llm::Summaries.brief(ticket) if ticket
  end
end
