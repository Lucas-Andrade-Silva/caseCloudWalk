module Llm
  # Brief do handoff e resumo de encerramento por LLM (ADR 0002, D5; ADR 0006, M3; ADR 0008). O template já foi
  # gravado e fica de reserva: sem LLM, nada se perde. Rodam em jobs, depois do commit.
  module Summaries
    SENDERS = { "customer" => "Cliente", "bot" => "Agente de IA", "analyst" => "Analista" }.freeze
    TRANSCRIPT_MESSAGES = 20

    module_function

    def brief(ticket, client: Llm.client)
      input = "#{transcript(ticket)}\nMotivo da escalação: #{ticket.escalation_reason}"
      result = client.call(task: "brief", input: input)
      ticket.with_lock do
        next ticket.record_event!(kind: "brief.summary_skipped", actor: "llm", data: { reason: result.error }) unless result.ok

        ticket.update!(handoff_brief: ticket.handoff_brief.to_h.merge(
          "llm_summary" => result.data["summary"], "llm_source" => result.source,
          "llm_model" => result.model, "llm_prompt_version" => result.prompt_version
        ))
        ticket.record_event!(kind: "brief.summarized", actor: "llm", data: meta(result))
      end
    end

    def closing(ticket, client: Llm.client)
      summary = ticket.closing_summary or return
      input = "#{transcript(ticket)}\nResolução: #{ticket.resolution_code}. #{ticket.resolution_note}".strip
      result = client.call(task: "closing", input: input)
      return ticket.record_event!(kind: "closing.summary_skipped", actor: "llm", data: { reason: result.error }) unless result.ok

      # A memória cita sempre o ticket de origem (ADR 0006, M3).
      summary.update!(text: "Ticket #{ticket.id}: #{result.data['summary']}", source: "llm")
      ticket.record_event!(kind: "closing.summarized", actor: "llm", data: meta(result))
    end

    def transcript(ticket)
      ticket.messages.order(:seq).last(TRANSCRIPT_MESSAGES)
            .map { |message| "#{SENDERS.fetch(message.sender, message.sender)}: #{message.body}" }.join("\n")
    end

    def meta(result) = { source: result.source, model: result.model, prompt_version: result.prompt_version }

    # Enfileira depois de todas as transações abertas confirmarem: o job precisa ver o que foi gravado.
    def enqueue_after_commit(job, ticket_id)
      return if Llm.mode == "off"

      ActiveRecord.after_all_transactions_commit { job.perform_async(ticket_id) }
    end
  end
end
