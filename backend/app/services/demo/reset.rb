module Demo
  # Deixa o banco de desenvolvimento pronto para a demo (ADR 0009): apaga as conversas (tickets, mensagens,
  # auditoria, incidentes, clientes, outbox) e mantém marcas, equipes, filas, regras e pessoas. Junta as equipes
  # duplicadas que os seeds antigos criavam. Com `history`, cria uma cliente sintética com dois atendimentos
  # anteriores, para mostrar a memória.
  #
  # Só para desenvolvimento: a tarefa `demo:reset` recusa outros ambientes. Rode com a pilha parada ou quieta;
  # o mapa aberto precisa ser recarregado.
  module Reset
    HISTORY_CUSTOMER = "demo-marina"

    # Ordem das chaves estrangeiras: quem aponta para alguém sai antes.
    CONVERSATION_DATA = [ OutboxEvent, ProcessedEvent, Decision, ClosingSummary, MemoryErasure, ConversationEvent,
                          Message, InboundEvent, Ticket, Incident, Customer ].freeze

    # Equipes que os seeds antigos criavam sem fila, ao lado da equipe dona da fila padrão da marca.
    LEGACY_TEAMS = { "atendimento-infinitepay" => "infinitepay", "atendimento-jim" => "jim" }.freeze

    HISTORY = [
      [ 12.days, "minha maquininha não liga depois da atualização",
        "Troca da maquininha aprovada; a nova foi enviada pelos Correios." ],
      [ 3.days, "a maquininha nova está sem sinal de internet",
        "Chip reconfigurado por telefone; voltou a passar cartão." ]
    ].freeze

    module_function

    def call(history: false, now: Time.current)
      ApplicationRecord.transaction do
        CONVERSATION_DATA.each(&:delete_all)
        merge_legacy_teams
        seed_history(now) if history
      end
    end

    def merge_legacy_teams
      LEGACY_TEAMS.each do |slug, brand_slug|
        legacy = Team.find_by(slug: slug)
        next unless legacy && TicketQueue.where(team: legacy).none?

        brand = Brand.find_by(slug: brand_slug)
        owner = brand && TicketQueue.default_for(brand)&.team
        next unless owner

        legacy.team_memberships.each { |membership| TeamMembership.find_or_create_by!(user_id: membership.user_id, team: owner) }
        legacy.destroy!
      end
    end

    def seed_history(now)
      brand = Brand.find_by!(slug: "infinitepay")
      queue = TicketQueue.find_by(slug: "maquininha-infinitepay") || TicketQueue.default_for(brand)
      customer = Customer.create!(brand: brand, external_id: HISTORY_CUSTOMER, name: "Marina Souza")

      HISTORY.each do |ago, request, resolution|
        opened = now - ago
        ticket = Ticket.create!(
          brand: brand, customer: customer, channel: "whatsapp", mode: "closed", priority: "p2", queue: queue,
          tags: [ "dispositivo" ], created_at: opened, updated_at: opened + 40.minutes,
          escalation_trigger: "agent_requested", escalation_reason: "device_issue", escalated_at: opened + 1.minute,
          closed_at: opened + 40.minutes, resolution_code: "resolved", resolution_note: resolution
        )
        ticket.append_message!(sender: "customer", body: request, created_at: opened)
        ticket.append_message!(sender: "analyst", body: resolution, created_at: opened + 30.minutes)
        ClosingSummary.create!(
          ticket: ticket, brand_id: brand.id, customer_id: customer.id,
          version: Memory::ClosingSummaryTemplate::VERSION, source: Memory::ClosingSummaryTemplate::SOURCE,
          text: Memory::ClosingSummaryTemplate.build(ticket), expires_at: ticket.closed_at + Memory.window_days.days
        )
      end
    end
  end
end
