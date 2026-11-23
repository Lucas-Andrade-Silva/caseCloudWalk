module Incidents
  # Percebe o pico (ADR 0009, W2): com um incidente aberto na chave do ticket, o ticket entra nele; sem, conta os
  # tickets abertos e soltos da mesma marca e chave na janela e, no limite, abre o incidente e liga todos.
  #
  # Roda num job depois do commit da entrada e do enriquecimento. Cada ticket é ligado na sua própria transação,
  # com o lock dele, para não disputar ordem de locks com a entrada.
  module Detect
    module_function

    def call(ticket, now: Time.current)
      return nil if ticket.mode == "closed"

      key, label = Incidents.key_for(ticket)
      return nil unless key

      incident = Incident.open.find_by(brand_id: ticket.brand_id, key: key)
      if incident
        link(ticket.id, incident)
        return incident
      end

      candidates = Ticket.open.where(brand_id: ticket.brand_id, incident_id: nil)
                         .where(created_at: (now - Incidents.window)..)
                         .where("#{KEY_SQL} = ?", key)
      return nil if candidates.count < Incidents.threshold

      incident, created = open_incident(ticket.brand, key, label, now)
      candidates.pluck(:id).each { |id| link(id, incident) }
      Llm::Summaries.enqueue_after_commit(IncidentSummaryJob, incident.id) if created
      incident
    end

    def open_incident(brand, key, label, now)
      incident = Incident.create!(brand: brand, key: key, label: label, opened_at: now,
                                  title: Template.title(brand, label), draft_reply: Template.draft_reply(brand, label))
      [ incident, true ]
    rescue ActiveRecord::RecordNotUnique
      [ Incident.open.find_by!(brand_id: brand.id, key: key), false ]
    end

    def link(ticket_id, incident)
      ticket = Ticket.find(ticket_id)
      ticket.with_lock do
        next if ticket.incident_id || ticket.mode == "closed"

        ticket.update!(incident: incident)
        ticket.record_event!(kind: "ticket.incident_linked", actor: "platform",
                             data: { incident_id: incident.id, key: incident.key })
      end
    end
  end
end
