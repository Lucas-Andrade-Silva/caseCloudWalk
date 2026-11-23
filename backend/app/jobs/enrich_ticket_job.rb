# Enriquece um ticket recém-aberto com o LLM (ADR 0008, L1). Sem nova tentativa: falhou, o ticket segue com o
# roteamento por regras, que já foi feito na entrada.
class EnrichTicketJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    Llm::Enrich.call(ticket) if ticket
  end
end
