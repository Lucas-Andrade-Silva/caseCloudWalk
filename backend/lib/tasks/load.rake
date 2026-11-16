require "net/http"

namespace :load do
  desc "Rajada de webhooks de canal com reentregas; grava o ledger. Uso: load:burst[count,rate,redeliver,seed]"
  task :burst, %i[count rate redeliver seed] => :environment do |_task, args|
    Rails.logger.level = Logger::WARN
    count = Integer(args.fetch(:count, 300))
    rate = Float(args.fetch(:rate, 10))
    redeliver = Float(args.fetch(:redeliver, 0.2))
    seed = Integer(args.fetch(:seed, 42))
    run = "#{seed}-#{SecureRandom.hex(3)}"
    plan = Load::BurstPlan.build(count: count, redeliver: redeliver, seed: seed, run: run)
    api = URI(ENV.fetch("SMOKE_API_URL", "http://api:3000"))
    secret = IntegrationConfig.channel_webhook_secrets.first
    ledger_path = Rails.root.join("tmp/ledgers/burst-#{run}.jsonl")
    FileUtils.mkdir_p(ledger_path.dirname)

    # Modelo aberto: cada envio tem horário marcado (índice / taxa), independente de o anterior ter
    # terminado. Vários trabalhadores evitam que uma resposta lenta atrase os próximos envios.
    jobs = Queue.new
    plan.each_with_index { |item, index| jobs << [ item, index / rate ] }
    workers = [ (rate / 2).ceil, 2 ].max.clamp(2, 32)
    results = Queue.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    threads = Array.new(workers) do
      Thread.new do
        Net::HTTP.start(api.host, api.port) do |http|
          while (job = jobs.pop(true) rescue nil)
            item, at = job
            wait = started + at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            sleep(wait) if wait.positive?

            body = { provider_message_id: item[:provider_message_id], brand: item[:brand],
                     customer: { external_id: item[:customer] }, text: item[:text] }.to_json
            id = SecureRandom.uuid
            timestamp = Time.now.to_i
            headers = {
              "Content-Type" => "application/json", "X-Webhook-Id" => id, "X-Webhook-Timestamp" => timestamp.to_s,
              "X-Webhook-Signature" => Webhooks::Signature.sign(id: id, timestamp: timestamp, body: body, secret: secret)
            }
            sent_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            status = begin
              http.post("/webhooks/channels/#{item[:channel]}", body, headers).code.to_i
            rescue StandardError => error
              error.class.name
            end
            elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - sent_at) * 1000).round
            results << item.slice(:channel, :provider_message_id, :redelivery).merge(status: status, ack_ms: elapsed_ms)
          end
        end
      end
    end
    threads.each(&:join)

    entries = Array.new(results.size) { results.pop }
    File.write(ledger_path, entries.map { |entry| JSON.generate(entry.transform_keys(&:to_s)) }.join("\n") + "\n")
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    acks = entries.map { |entry| entry[:ack_ms] }.sort
    percentile = ->(p) { acks[((acks.size - 1) * p).round] }

    puts "rajada #{run}: #{entries.size} envios (#{plan.count { |i| i[:redelivery] }} reentregas) em #{took.round(1)} s"
    puts "status: #{entries.group_by { |entry| entry[:status] }.transform_values(&:size)}"
    puts "ACK do webhook (ambiente de desenvolvimento, não é medida): p50 #{percentile.(0.5)} ms, p99 #{percentile.(0.99)} ms"
    puts "ledger: #{ledger_path.relative_path_from(Rails.root)}"
  end
end

namespace :invariants do
  desc "Espera o fluxo esvaziar e confere os quatro invariantes. Uso: invariants:check[ledger,espera_s]"
  task :check, %i[ledger wait] => :environment do |_task, args|
    Rails.logger.level = Logger::WARN
    ledger = File.readlines(args.fetch(:ledger), chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
    wait = Integer(args.fetch(:wait, 120))
    pairs = ledger.map { |entry| [ entry["channel"], entry["provider_message_id"] ] }.uniq

    # Esvaziou quando o outbox não tem nada pendente e nenhum ticket do ledger espera o agente.
    deadline = Time.current + wait
    loop do
      ticket_ids = Message.joins(:inbound_event)
                          .where(inbound_events: { provider_message_id: pairs.map(&:last) }).distinct.pluck(:ticket_id)
      waiting = Ticket.where(id: ticket_ids, mode: "ai").where.not(awaiting_agent_since: nil).count
      pending = OutboxEvent.pending.count
      break if (waiting.zero? && pending.zero?) || Time.current > deadline

      puts "aguardando: #{pending} no outbox, #{waiting} ticket(s) esperando o agente"
      sleep 5
    end

    report = Invariants::Checker.call(ledger: ledger)
    puts JSON.pretty_generate(report.except(:violations))
    report[:violations].each do |name, items|
      puts "#{name}: #{items.size} violação(ões)"
      items.first(10).each { |item| puts "  #{item}" }
    end
    puts report[:ok] ? "INVARIANTES OK" : "INVARIANTES VIOLADOS"
    exit(1) unless report[:ok]
  end
end
