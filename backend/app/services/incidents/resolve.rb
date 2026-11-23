module Incidents
  # "Responder a todos" (ADR 0009, W1): numa transação, o analista assume cada ticket aberto do incidente,
  # manda a mesma resposta e fecha com a resolução. Ticket com outro analista fica de fora e volta na lista de
  # pulados: a plataforma não tira o atendimento de ninguém. Os locks seguem a ordem dos ids.
  class Resolve
    class Invalid < StandardError; end
    class AlreadyResolved < StandardError; end

    Outcome = Data.define(:closed, :skipped)

    def self.call(...) = new(...).call

    def initialize(incident:, analyst:, text:, resolution_code: "resolved", now: Time.current)
      @incident = incident
      @analyst = analyst
      @text = text.to_s.strip
      @code = resolution_code.presence || "resolved"
      @now = now
    end

    def call
      validate!
      ApplicationRecord.transaction do
        @incident.lock!
        raise AlreadyResolved unless @incident.open?

        closed = 0
        skipped = []
        @incident.tickets.open.order(:id).each do |ticket|
          ticket.lock!
          next if ticket.mode == "closed"

          if ticket.human? && ticket.assignee_id != @analyst.id
            skipped << { id: ticket.id, reason: "other_analyst" }
            next
          end

          answer_and_close(ticket)
          closed += 1
        end
        @incident.update!(status: "resolved", resolved_at: @now, resolved_by: @analyst)
        Outcome.new(closed: closed, skipped: skipped)
      end
    end

    private

    def validate!
      raise Invalid, "text é obrigatório" if @text.empty?
      return if Ticket::RESOLUTION_CODES.include?(@code)

      raise Invalid, "resolution_code precisa ser um de: #{Ticket::RESOLUTION_CODES.join(', ')}"
    end

    def answer_and_close(ticket)
      take(ticket)
      message = ticket.append_message!(sender: "analyst", body: @text)
      first_response = ticket.first_human_response_at.nil?
      ticket.update!(first_human_response_at: message.created_at) if first_response
      ticket.record_event!(kind: "message.sent", actor: "analyst",
                           data: { message_id: message.id, seq: message.seq, assignee_id: @analyst.id,
                                   first_response: first_response, incident_id: @incident.id })
      Tickets::Close.call(ticket: ticket, analyst: @analyst, resolution_code: @code,
                          resolution_note: "Incidente #{@incident.id}", now: @now)
    end

    def take(ticket)
      if ticket.ai?
        Handoff::Escalate.call(ticket: ticket, trigger: "incident", reason: "incident", actor: "analyst",
                               target: "human", assignee: @analyst, data: { incident_id: @incident.id })
        Handoff::Assign.call(ticket: ticket, analyst: @analyst, trigger: "incident")
      elsif ticket.mode == "pending_human"
        Handoff::Assign.call(ticket: ticket, analyst: @analyst, trigger: "incident")
      end
    end
  end
end
