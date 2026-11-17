namespace :outbox do
  desc "Publica o outbox no Kafka em laço (processo de longa duração)"
  task relay: :environment do
    # O laço consulta o banco várias vezes por segundo; em nível debug o SQL afogaria o log.
    Rails.logger.level = Logger::INFO

    process = Outbox::RelayProcess.new
    %w[INT TERM].each { |signal| trap(signal) { process.stop } }

    Rails.logger.info("[outbox relay] iniciado")
    process.run
    Rails.logger.info("[outbox relay] encerrado")
  end

  desc "Lista os eventos estacionados (recusados de vez pelo broker)"
  task dead: :environment do
    Rails.logger.level = Logger::WARN
    events = OutboxEvent.dead
    puts "#{events.size} evento(s) estacionado(s)"
    events.each do |event|
      held = OutboxEvent.where(key: event.key, published_at: nil, dead_at: nil, discarded_at: nil).count
      puts "  ##{event.id} #{event.topic} chave #{event.key}, #{event.attempts} tentativa(s), " \
           "#{held} retido(s) atrás dele: #{event.last_error}"
    end
  end

  desc "Volta um evento estacionado para a fila"
  task :retry_dead, [ :id ] => :environment do |_task, args|
    Rails.logger.level = Logger::WARN
    OutboxEvent.dead.find(args.fetch(:id)).retry!
    puts "evento #{args[:id]} de volta à fila"
  end

  desc "Descarta um evento estacionado e libera os eventos retidos do mesmo ticket"
  task :discard_dead, [ :id ] => :environment do |_task, args|
    Rails.logger.level = Logger::WARN
    OutboxEvent.dead.find(args.fetch(:id)).discard!
    puts "evento #{args[:id]} descartado"
  end
end
