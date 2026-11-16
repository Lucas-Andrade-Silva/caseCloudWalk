# Dados mínimos para a plataforma funcionar. Idempotente: pode rodar a cada subida.
#
# O banco de teste fica vazio: cada teste cria o que precisa. (O db:prepare chama os seeds ao criar
# um banco novo, e marcas pré-gravadas colidiriam com as que os testes criam.)
return if Rails.env.test?

PriorityLevel.ensure_defaults!

# Cada marca com a sua fila humana padrão (ADR 0004, H2).
[ %w[infinitepay InfinitePay], %w[jim JIM] ].each do |slug, name|
  brand = Brand.find_or_create_by!(slug: slug) { |record| record.name = name }
  TicketQueue.find_or_create_by!(slug: "#{slug}-atendimento") do |queue|
    queue.brand = brand
    queue.name = "Atendimento #{name}"
    queue.default = true
  end
end

# Analistas sintéticos para desenvolvimento e demo. Tokens fixos de desenvolvimento, nunca de produção.
if Rails.env.development?
  { "Ana" => %w[infinitepay], "Bruno" => %w[jim], "Carla" => %w[infinitepay jim] }.each do |name, brands|
    analyst = User.find_or_create_by!(token_digest: User.digest("dev-analyst-#{name.downcase}")) do |user|
      user.name = name
      user.role = "analyst"
    end
    brands.each do |slug|
      QueueMembership.find_or_create_by!(user: analyst, queue: TicketQueue.find_by!(slug: "#{slug}-atendimento"))
    end
  end
end

# O agente de IA entra como usuário bot. O token vem do ambiente; só o hash vai para o banco.
if (token = ENV["BOT_API_TOKEN"].presence)
  User.find_or_create_by!(token_digest: User.digest(token)) do |user|
    user.name = "Agente de IA"
    user.role = "bot"
  end
end
