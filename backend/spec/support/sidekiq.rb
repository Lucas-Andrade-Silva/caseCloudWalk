require "sidekiq/testing"

# Jobs enfileirados nos testes ficam em memória: nunca chegam ao Redis da pilha de desenvolvimento.
Sidekiq::Testing.fake!

RSpec.configure do |config|
  config.before { Sidekiq::Worker.clear_all }
end
