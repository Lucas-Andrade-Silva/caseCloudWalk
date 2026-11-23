require "prometheus/client"

module Observability
  # Medidas do domínio para o Prometheus (ADR 0008, O3), lidas do banco a cada coleta: valem para a API
  # inteira, não só para o processo que respondeu, e não precisam de contador espalhado pelo código.
  module DomainMetrics
    MODES = %w[ai pending_human human].freeze

    module_function

    def registry = Prometheus::Client.registry

    def gauge(name, docstring, labels = [])
      registry.get(name) || registry.gauge(name, docstring: docstring, labels: labels)
    end

    def refresh!(now: Time.current)
      pending = OutboxEvent.pending.unscope(:order)
      oldest_pending = pending.minimum(:created_at)
      gauge(:helpdesk_outbox_pending_events, "Eventos do outbox ainda não entregues ao broker").set(pending.count)
      gauge(:helpdesk_outbox_oldest_pending_age_seconds, "Idade do evento pendente mais antigo")
        .set(oldest_pending ? (now - oldest_pending).round : 0)
      gauge(:helpdesk_outbox_parked_events, "Eventos estacionados (recusados de vez pelo broker)").set(OutboxEvent.dead.unscope(:order).count)

      brands = Brand.pluck(:id, :slug).to_h
      open = Ticket.open.group(:brand_id, :mode).count
      waiting_human = Ticket.where(mode: "pending_human").group(:brand_id)
      waiting_count = waiting_human.count
      oldest_waiting = waiting_human.minimum(:escalated_at)
      waiting_agent = Ticket.where(mode: "ai").where.not(awaiting_agent_since: nil).group(:brand_id).count

      open_gauge = gauge(:helpdesk_open_tickets, "Tickets abertos por marca e modo", %i[brand mode])
      human_gauge = gauge(:helpdesk_tickets_waiting_human, "Tickets escalados esperando um analista", %i[brand])
      age_gauge = gauge(:helpdesk_oldest_waiting_human_age_seconds, "Espera do ticket escalado mais antigo", %i[brand])
      agent_gauge = gauge(:helpdesk_tickets_waiting_agent, "Tickets com o cliente esperando o agente", %i[brand])

      brands.each do |id, slug|
        MODES.each { |mode| open_gauge.set(open.fetch([ id, mode ], 0), labels: { brand: slug, mode: mode }) }
        human_gauge.set(waiting_count.fetch(id, 0), labels: { brand: slug })
        age_gauge.set(oldest_waiting[id] ? (now - oldest_waiting[id]).round : 0, labels: { brand: slug })
        agent_gauge.set(waiting_agent.fetch(id, 0), labels: { brand: slug })
      end
    end
  end
end
