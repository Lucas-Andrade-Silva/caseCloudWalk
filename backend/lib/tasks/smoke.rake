require "net/http"

# Testes de fumaça contra a pilha no ar (docker compose up). Não fazem parte da suíte: provam que os
# processos reais (relay, broker, Kafka, mock, Sidekiq) estão ligados entre si.
module Smoke
  module_function

  def api = URI(ENV.fetch("SMOKE_API_URL", "http://api:3000"))
  def timeout = Integer(ENV.fetch("SMOKE_TIMEOUT", "60"))
  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def http(method, path, body: nil, headers: {})
    request = Net::HTTP.const_get(method.capitalize).new(path, { "Content-Type" => "application/json" }.merge(headers))
    request.body = body if body
    response = Net::HTTP.start(api.host, api.port) { |connection| connection.request(request) }
    [ response.code.to_i, response.body.to_s.empty? ? nil : JSON.parse(response.body) ]
  end

  def send_customer_message(customer, provider_message_id, text)
    body = { provider_message_id: provider_message_id, brand: "infinitepay",
             customer: { external_id: customer, name: "Cliente de teste" }, text: text }.to_json
    id = SecureRandom.uuid
    timestamp = Time.now.to_i
    signature = Webhooks::Signature.sign(id: id, timestamp: timestamp, body: body,
                                         secret: IntegrationConfig.channel_webhook_secrets.first)
    http(:post, "/webhooks/channels/whatsapp", body: body, headers: {
      "X-Webhook-Id" => id, "X-Webhook-Timestamp" => timestamp.to_s, "X-Webhook-Signature" => signature
    })
  end

  def wait_until(what)
    deadline = clock + timeout
    until (value = yield)
      abort "FALHOU: #{what} não aconteceu em #{timeout} s" if clock > deadline
      sleep 0.2
    end
    value
  end

  def check(condition, message)
    abort "FALHOU: #{message}" unless condition
  end
end

namespace :smoke do
  desc "Webhook de canal entra e a resposta do agente aparece no ticket"
  task round_trip: :environment do
    Rails.logger.level = Logger::WARN
    run_id = SecureRandom.hex(4)
    customer = "smoke-#{run_id}"
    # "[responder]" impede o agente simulado de escalar esta conversa.
    text = "minha maquininha não liga [responder]"

    status, created = Smoke.send_customer_message(customer, "#{customer}-1", text)
    Smoke.check(status == 201, "o webhook respondeu #{status}: #{created}")
    puts "1. webhook aceito: ticket #{created['ticket_id']}, seq #{created['seq']}"

    status, repeated = Smoke.send_customer_message(customer, "#{customer}-1", text)
    Smoke.check(status == 200 && repeated["duplicate"], "a reentrega respondeu #{status}: #{repeated}")
    puts "2. reentrega do webhook reconhecida como duplicata"

    ticket = Ticket.find(created["ticket_id"])
    reply = Smoke.wait_until("a resposta do agente") { ticket.messages.find_by(sender: "bot") }
    elapsed = ((reply.created_at - ticket.messages.find_by!(seq: 1).created_at) * 1000).round
    puts "3. resposta do agente gravada em #{elapsed} ms: seq #{reply.seq}, em resposta à #{reply.in_reply_to_seq}"

    sleep 2 # dá tempo de uma duplicata indevida aparecer
    messages = ticket.messages.order(:seq).pluck(:seq, :sender)
    events = ticket.conversation_events.order(:id).pluck(:kind)
    Smoke.check(messages == [ [ 1, "customer" ], [ 2, "bot" ] ], "mensagens inesperadas #{messages}")
    Smoke.check(events == %w[ticket.opened message.received message.sent], "linha do tempo inesperada #{events}")
    Smoke.check(ticket.reload.awaiting_agent_since.nil?, "o ticket ainda aparece esperando o agente")
    puts "4. ticket com 2 mensagens (cliente, bot), linha do tempo #{events.join(' > ')}"
    puts "OK"
  end

  desc "O agente pede escalação, o analista puxa o ticket, responde dentro do prazo e fecha"
  task escalation: :environment do
    Rails.logger.level = Logger::WARN
    customer = "smoke-#{SecureRandom.hex(4)}"
    analyst = { "Authorization" => "Bearer #{ENV.fetch('SMOKE_ANALYST_TOKEN', 'dev-analyst-ana')}" }

    # Esvazia a fila da Ana, para "pegar o próximo" trazer o ticket deste teste.
    while Smoke.http(:post, "/api/work/next", headers: analyst).first == 200; end

    # "[escalar]" faz o agente simulado pedir escalação.
    status, created = Smoke.send_customer_message(customer, "#{customer}-1", "quero falar com uma pessoa [escalar]")
    Smoke.check(status == 201, "o webhook respondeu #{status}: #{created}")
    ticket = Ticket.find(created["ticket_id"])
    puts "1. mensagem do cliente aceita: ticket #{ticket.id}"

    Smoke.wait_until("a escalação pedida pelo agente") { ticket.reload.mode == "pending_human" }
    brief = ticket.handoff_brief
    puts "2. agente pediu escalação: fila #{ticket.queue.slug}, #{ticket.priority}, prazo " \
         "#{ticket.first_response_due_at.strftime('%H:%M:%S')}, motivo #{ticket.escalation_reason}"
    puts "   brief: #{brief['summary']}"

    status, assigned = Smoke.http(:post, "/api/work/next", headers: analyst)
    Smoke.check(status == 200 && assigned["id"] == ticket.id, "pegar o próximo devolveu #{status}: #{assigned}")
    puts "3. analista puxou o ticket: modo #{assigned['mode']}, epoch #{assigned['handoff_epoch']}"

    status, sent = Smoke.http(:post, "/api/tickets/#{ticket.id}/messages", headers: analyst,
                                                                          body: { text: "Oi, aqui é a Ana." }.to_json)
    Smoke.check(status == 201 && sent["sla_met"] == true, "a resposta do analista devolveu #{status}: #{sent}")
    status, = Smoke.http(:post, "/api/tickets/#{ticket.id}/close", headers: analyst)
    Smoke.check(status == 200, "fechar devolveu #{status}")

    events = ticket.conversation_events.order(:id).pluck(:kind)
    expected = %w[ticket.opened message.received message.sent ticket.escalated ticket.assigned message.sent ticket.closed]
    Smoke.check(events == expected, "linha do tempo inesperada #{events}")
    puts "4. analista respondeu dentro do prazo e fechou: #{events.join(' > ')}"
    puts "OK"
  end

  desc "A regra publicada manda a mensagem de crédito de valor alto para a fila e a prioridade certas"
  task routing: :environment do
    Rails.logger.level = Logger::WARN
    customer = "smoke-#{SecureRandom.hex(4)}"

    status, created = Smoke.send_customer_message(customer, "#{customer}-1",
                                                  "meu empréstimo de R$ 12.000,00 não caiu [escalar]")
    Smoke.check(status == 201, "o webhook respondeu #{status}: #{created}")
    ticket = Ticket.find(created["ticket_id"])
    opening = Decision.find_by!(ticket: ticket, step: "routing.opening")
    puts "1. abertura: regra #{opening.matched_rule_id} (versão #{opening.rule_set_version}) -> " \
         "#{opening.output['queue']}, #{opening.output['priority']}, tags #{opening.output['tags']}"
    Smoke.check(opening.matched_rule_id == "credito-alto-valor", "regra inesperada #{opening.matched_rule_id}")

    Smoke.wait_until("a escalação") { ticket.reload.mode == "pending_human" }
    Smoke.check(ticket.queue.slug == "credito-infinitepay" && ticket.priority == "p1",
                "fila ou prioridade inesperada: #{ticket.queue.slug}, #{ticket.priority}")
    minutes = ((ticket.first_response_due_at - ticket.escalated_at) / 60).round
    puts "2. escalado para #{ticket.queue.slug} (equipe #{ticket.queue.team.name}), #{ticket.priority}, " \
         "prazo de #{minutes} min, tags #{ticket.tags}"
    puts "OK"
  end

  desc "Com o agente fora do ar, o vigia do Sidekiq escala a conversa (pare o mock-agent antes)"
  task agent_silence: :environment do
    Rails.logger.level = Logger::WARN
    customer = "smoke-#{SecureRandom.hex(4)}"

    status, created = Smoke.send_customer_message(customer, "#{customer}-1", "olá? [responder]")
    Smoke.check(status == 201, "o webhook respondeu #{status}: #{created}")
    ticket = Ticket.find(created["ticket_id"])
    started = Time.current
    puts "1. mensagem aceita com o agente fora do ar: ticket #{ticket.id}"

    Smoke.wait_until("a escalação pelo vigia") { ticket.reload.mode == "pending_human" }
    Smoke.check(ticket.escalation_trigger == "agent_timeout", "gatilho inesperado #{ticket.escalation_trigger}")
    puts "2. vigia escalou em #{(ticket.escalated_at - started).round(1)} s (limite de silêncio: 30 s, " \
         "vigia a cada 5 s): gatilho #{ticket.escalation_trigger}"
    puts "OK"
  end
end
