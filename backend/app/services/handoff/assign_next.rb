module Handoff
  # "Pegar o próximo" (ADR 0004, H4): entrega ao analista o ticket escalado de prazo mais próximo nas
  # filas dele. Devolve o ticket ou nil se não há nada esperando.
  #
  # FOR UPDATE SKIP LOCKED faz analistas simultâneos pularem o ticket que outro está pegando, em vez de
  # esperar por ele ou pegar o mesmo.
  class AssignNext
    def self.call(...) = new(...).call

    # O que espera nas filas do analista, na ordem em que "pegar o próximo" entrega.
    def self.waiting_for(analyst)
      Ticket.where(mode: "pending_human", assignee_id: nil, queue_id: analyst.queues.select(:id))
            .order(:first_response_due_at, :escalated_at, :id)
    end

    def initialize(analyst:)
      @analyst = analyst
    end

    def call
      ApplicationRecord.transaction do
        ticket = self.class.waiting_for(@analyst)
                       .lock("FOR UPDATE SKIP LOCKED")
                       .first
        next nil unless ticket

        Assign.call(ticket: ticket, analyst: @analyst, trigger: "work_next")
      end
    end
  end
end
