namespace :demo do
  desc "Apaga as conversas do banco de desenvolvimento e cria o histórico da demo (HISTORY=false para não criar)"
  task reset: :environment do
    abort "demo:reset só roda em desenvolvimento" unless Rails.env.development?

    Demo::Reset.call(history: ENV.fetch("HISTORY", "true") == "true")
    puts "Banco de demo pronto: #{Ticket.count} tickets, #{Customer.count} clientes, #{Team.count} equipes."
  end
end
