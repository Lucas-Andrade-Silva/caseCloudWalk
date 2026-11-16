# Dados mínimos para a plataforma funcionar. Idempotente: pode rodar a cada subida.
#
# O banco de teste fica vazio: cada teste cria o que precisa. (O db:prepare chama os seeds ao criar
# um banco novo, e marcas pré-gravadas colidiriam com as que os testes criam.)
return if Rails.env.test?

PriorityLevel.ensure_defaults!

brands = [ %w[infinitepay InfinitePay], %w[jim JIM] ].to_h do |slug, name|
  [ slug, Brand.find_or_create_by!(slug: slug) { |record| record.name = name } ]
end

team = ->(slug, name) { Team.find_or_create_by!(slug: slug) { |record| record.name = name } }
queue = lambda do |slug, name, brand, owner, default: false|
  TicketQueue.find_or_create_by!(slug: slug) do |record|
    record.assign_attributes(brand: brands.fetch(brand), team: owner, name: name, default: default)
  end
end

# Equipes e filas de exemplo (ADR 0005, R1). Cada marca tem a sua fila padrão (ADR 0004, H2).
general_ip = team.("atendimento-infinitepay", "Atendimento InfinitePay")
general_jim = team.("atendimento-jim", "Atendimento JIM")
credit = team.("credito", "Crédito")
device = team.("dispositivo", "Dispositivo")

queue.("infinitepay-atendimento", "Atendimento InfinitePay", "infinitepay", general_ip, default: true)
queue.("jim-atendimento", "Atendimento JIM", "jim", general_jim, default: true)
queue.("credito-infinitepay", "Crédito InfinitePay", "infinitepay", credit)
queue.("credito-jim", "Crédito JIM", "jim", credit)
queue.("maquininha-infinitepay", "Maquininha InfinitePay", "infinitepay", device)

# Regras iniciais publicadas, só se a marca ainda não tem nenhuma versão.
keywords = ->(*words) { { "fact" => "message_text", "op" => "contains_any", "value" => words } }
initial_rules = {
  "infinitepay" => [
    { "id" => "credito-alto-valor", "name" => "Crédito acima de R$ 5 mil",
      "when" => { "all" => [ keywords.("crédito", "empréstimo"), { "fact" => "amount", "op" => "gte", "value" => 5000 } ] },
      "then" => { "queue" => "credito-infinitepay", "priority" => "p1", "tags" => [ "alto_valor" ] } },
    { "id" => "credito", "name" => "Crédito",
      "when" => keywords.("crédito", "empréstimo", "limite"),
      "then" => { "queue" => "credito-infinitepay", "priority" => "p2" } },
    { "id" => "maquininha", "name" => "Maquininha",
      "when" => keywords.("maquininha", "máquina", "não liga", "bateria"),
      "then" => { "queue" => "maquininha-infinitepay", "priority" => "p2", "tags" => [ "dispositivo" ] } },
    { "id" => "recontato", "name" => "Cliente voltou 3 vezes em 24 h",
      "when" => { "fact" => "contacts_24h", "op" => "gte", "value" => 3 },
      "then" => { "priority" => "p2", "tags" => [ "recontato" ] } }
  ],
  "jim" => [
    { "id" => "credit", "name" => "Credit",
      "when" => keywords.("credit", "loan"),
      "then" => { "queue" => "credito-jim", "priority" => "p2" } }
  ]
}
initial_rules.each do |slug, rules|
  brand = brands.fetch(slug)
  next if RuleSet.exists?(brand: brand)

  RuleSet.create!(brand: brand, version: 1, rules: rules).publish!
end

# Pessoas sintéticas para desenvolvimento e demo. Tokens fixos de desenvolvimento, nunca de produção.
if Rails.env.development?
  person = lambda do |name, role|
    User.find_or_create_by!(token_digest: User.digest("dev-#{role}-#{name.downcase}")) do |user|
      user.name = name
      user.role = role
    end
  end

  { "Ana" => [ general_ip, device ], "Bruno" => [ general_jim ], "Carla" => [ general_ip, general_jim, credit ] }
    .each do |name, teams|
      analyst = person.(name, "analyst")
      teams.each { |member_of| TeamMembership.find_or_create_by!(user: analyst, team: member_of) }
    end
  person.("Olivia", "ops")
end

# O agente de IA entra como usuário bot. O token vem do ambiente; só o hash vai para o banco.
if (token = ENV["BOT_API_TOKEN"].presence)
  User.find_or_create_by!(token_digest: User.digest(token)) do |user|
    user.name = "Agente de IA"
    user.role = "bot"
  end
end
