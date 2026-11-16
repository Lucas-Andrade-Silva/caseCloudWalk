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
end
