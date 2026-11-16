require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |file| require file }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Cada teste roda numa transação desfeita no fim. Testes que precisam de conexões reais
  # (concorrência, Kafka) desligam isso no próprio grupo e limpam o que gravaram.
  config.use_transactional_fixtures = true
  # spec/requests vira teste de requisição (get, post, response) pelo caminho do arquivo.
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
