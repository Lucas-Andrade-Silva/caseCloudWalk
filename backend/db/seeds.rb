# Dados mínimos para a plataforma funcionar. Idempotente: pode rodar a cada subida.
#
# O banco de teste fica vazio: cada teste cria o que precisa. (O db:prepare chama os seeds ao criar
# um banco novo, e marcas pré-gravadas colidiriam com as que os testes criam.)
return if Rails.env.test?

[ %w[infinitepay InfinitePay], %w[jim JIM] ].each do |slug, name|
  Brand.find_or_create_by!(slug: slug) { |brand| brand.name = name }
end

# O agente de IA entra como usuário bot. O token vem do ambiente; só o hash vai para o banco.
if (token = ENV["BOT_API_TOKEN"].presence)
  User.find_or_create_by!(token_digest: User.digest(token)) do |user|
    user.name = "Agente de IA"
    user.role = "bot"
  end
end
