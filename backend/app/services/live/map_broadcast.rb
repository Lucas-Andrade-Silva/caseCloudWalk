module Live
  # Publica cada mudança de ticket no canal da marca, para o mapa vivo (ADR 0007, I13).
  #
  # O mapa não é caminho crítico: se o Redis estiver fora, a mudança já foi gravada e a requisição segue.
  # Só registra o aviso; o navegador recupera pelo polling de reserva.
  module MapBroadcast
    module_function

    def stream(brand_slug) = "map:#{brand_slug}"

    def ticket_changed(ticket)
      message = if ticket.mode == "closed"
        { type: "ticket.removed", id: ticket.id }
      else
        { type: "ticket.upsert", ticket: MapItem.call(ticket) }
      end
      ActionCable.server.broadcast(stream(ticket.brand.slug), message)
    rescue StandardError => error
      Rails.logger.warn("[mapa vivo] evento do ticket #{ticket.id} não publicado: #{error.class}: #{error.message}")
    end
  end
end
