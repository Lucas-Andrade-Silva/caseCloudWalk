require "net/http"

namespace :smoke do
  desc "Ponta a ponta com a pilha no ar: webhook de canal entra e a resposta do agente aparece no ticket"
  task round_trip: :environment do
    Rails.logger.level = Logger::WARN
    api = URI(ENV.fetch("SMOKE_API_URL", "http://api:3000"))
    timeout = Integer(ENV.fetch("SMOKE_TIMEOUT", "60"))
    run_id = SecureRandom.hex(4)

    send_webhook = lambda do |provider_message_id, text|
      body = { provider_message_id: provider_message_id, brand: "infinitepay",
               customer: { external_id: "smoke-#{run_id}", name: "Cliente de teste" }, text: text }.to_json
      id = SecureRandom.uuid
      timestamp = Time.now.to_i
      headers = {
        "Content-Type" => "application/json",
        "X-Webhook-Id" => id,
        "X-Webhook-Timestamp" => timestamp.to_s,
        "X-Webhook-Signature" => Webhooks::Signature.sign(
          id: id, timestamp: timestamp, body: body, secret: IntegrationConfig.channel_webhook_secrets.first
        )
      }
      response = Net::HTTP.start(api.host, api.port) { |http| http.post("/webhooks/channels/whatsapp", body, headers) }
      [ response.code.to_i, JSON.parse(response.body) ]
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, created = send_webhook.call("smoke-#{run_id}-1", "minha maquininha não liga")
    abort "FALHOU: o webhook respondeu #{status}: #{created}" unless status == 201
    puts "1. webhook aceito: ticket #{created['ticket_id']}, seq #{created['seq']}"

    # Reentrega do mesmo webhook: não pode gerar segunda mensagem nem segunda resposta.
    status, repeated = send_webhook.call("smoke-#{run_id}-1", "minha maquininha não liga")
    abort "FALHOU: a reentrega respondeu #{status}: #{repeated}" unless status == 200 && repeated["duplicate"]
    puts "2. reentrega do webhook reconhecida como duplicata"

    ticket = Ticket.find(created["ticket_id"])
    deadline = started + timeout
    reply = nil
    until (reply = ticket.messages.find_by(sender: "bot")) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.2
    end
    abort "FALHOU: nenhuma resposta do agente em #{timeout} s" unless reply

    elapsed = ((reply.created_at - ticket.messages.find_by!(seq: 1).created_at) * 1000).round
    puts "3. resposta do agente gravada em #{elapsed} ms: seq #{reply.seq}, em resposta à #{reply.in_reply_to_seq}"
    puts "   \"#{reply.body}\""

    sleep 2 # dá tempo de uma duplicata indevida aparecer
    messages = ticket.messages.order(:seq).pluck(:seq, :sender)
    events = ticket.conversation_events.order(:id).pluck(:kind)
    pending = OutboxEvent.pending.count
    abort "FALHOU: mensagens inesperadas #{messages}" unless messages == [ [ 1, "customer" ], [ 2, "bot" ] ]
    abort "FALHOU: linha do tempo inesperada #{events}" unless events == %w[ticket.opened message.received message.sent]
    abort "FALHOU: #{pending} evento(s) parado(s) no outbox" unless pending.zero?

    puts "4. ticket com 2 mensagens (cliente, bot), linha do tempo #{events.join(' > ')}, outbox vazio"
    puts "OK"
  end
end
