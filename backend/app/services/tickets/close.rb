module Tickets
  # Fecha um ticket em atendimento humano com a resolução (ADR 0006, M2) e grava o resumo de encerramento
  # (M3). Quem chama segura o lock do ticket; tudo vale junto ou nada vale.
  class Close
    class Invalid < StandardError; end

    def self.call(...) = new(...).call

    def initialize(ticket:, analyst:, resolution_code:, resolution_note: nil, now: Time.current)
      @ticket = ticket
      @analyst = analyst
      @code = resolution_code.to_s
      @note = resolution_note.to_s.strip.presence
      @now = now
    end

    def call
      validate!
      @ticket.transition_to!("closed", closed_at: @now, resolution_code: @code, resolution_note: @note)
      @ticket.record_event!(kind: "ticket.closed", actor: "analyst",
                            data: { assignee_id: @analyst.id, resolution_code: @code })
      ClosingSummary.create!(
        ticket: @ticket, brand_id: @ticket.brand_id, customer_id: @ticket.customer_id,
        version: Memory::ClosingSummaryTemplate::VERSION, source: Memory::ClosingSummaryTemplate::SOURCE,
        text: Memory::ClosingSummaryTemplate.build(@ticket), expires_at: @now + Memory.window_days.days
      )
      @ticket
    end

    private

    def validate!
      unless Ticket::RESOLUTION_CODES.include?(@code)
        raise Invalid, "resolution_code precisa ser um de: #{Ticket::RESOLUTION_CODES.join(', ')}"
      end
      return unless @note && @note.length > Ticket::RESOLUTION_NOTE_MAX

      raise Invalid, "resolution_note passa de #{Ticket::RESOLUTION_NOTE_MAX} caracteres"
    end
  end
end
