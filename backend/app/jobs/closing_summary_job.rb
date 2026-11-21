# Resumo de encerramento por LLM para a memória do cliente (ADR 0006, M3; ADR 0008). Sem nova tentativa: o
# resumo por template já está gravado.
class ClosingSummaryJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    Llm::Summaries.closing(ticket) if ticket
  end
end
