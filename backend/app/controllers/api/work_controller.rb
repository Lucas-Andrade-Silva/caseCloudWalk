module Api
  # "Pegar o próximo" (ADR 0004, H4).
  class WorkController < AnalystController
    def next
      ticket = Handoff::AssignNext.call(analyst: current_analyst)
      return head :no_content unless ticket

      render json: ticket_summary(ticket)
    end
  end
end
