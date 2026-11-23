namespace :experiment do
  desc "Converte a saída JSON do k6 no ledger. Uso: experiment:ledger[k6_json,nome:mult:seg;...,ledger_saida]"
  task :ledger, %i[k6_json stages out] => :environment do |_task, args|
    # Mesmo formato do gerador: "nome:multiplicador:segundos;..." (sem vírgula, que o rake usa entre argumentos).
    stages = args.fetch(:stages).split(";").map { |stage| stage.split(":") }.map { |name, _multiplier, seconds| [ name, Integer(seconds) ] }
    ledger = Experiment::K6Ledger.convert(File.foreach(args.fetch(:k6_json)), stages: stages)
    File.write(args.fetch(:out), ledger.map { |entry| JSON.generate(entry) }.join("\n") + "\n")
    puts "ledger: #{args.fetch(:out)} (#{ledger.size} envios)"
  end

  desc "Resumo da rodada por fase (ACK, ponta a ponta, escaladas, outbox). Uso: experiment:report[ledger,json_saida]"
  task :report, %i[ledger out] => :environment do |_task, args|
    Rails.logger.level = Logger::WARN
    ledger = File.readlines(args.fetch(:ledger), chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
    report = Experiment::Report.call(ledger: ledger)
    File.write(args.fetch(:out), JSON.pretty_generate(report)) if args[:out]

    puts format("%-10s %7s %7s %6s %6s %10s %10s %9s %8s %10s %10s %10s", "fase", "envios", "msg/s", "reent", "recus",
                "ACK p50", "ACK p99", "respond", "escal", "e2e p50", "e2e p99", "outbox p99")
    report[:stages].each do |row|
      ms = ->(value) { value.nil? ? "—" : "#{value.round} ms" }
      puts format("%-10s %7d %7s %6d %6d %10s %10s %9d %8d %10s %10s %10s", row[:stage], row[:sent], row[:rate_per_s] || "—", row[:redeliveries],
                  row[:refused], ms.(row[:ack_p50_ms]), ms.(row[:ack_p99_ms]), row[:answered], row[:escalated],
                  ms.(row[:e2e_p50_ms]), ms.(row[:e2e_p99_ms]), ms.(row[:outbox_p99_ms]))
    end
  end
end
