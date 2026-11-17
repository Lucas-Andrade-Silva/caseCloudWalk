module Load
  # Plano de uma rajada de mensagens sintéticas para testar a plataforma antes do k6 (spec 05).
  # Determinístico pela seed: mesmas mensagens, mesmos clientes, mesmas reentregas.
  #
  # `run` entra nos ids das mensagens, para rodar a mesma seed de novo sem cair no dedupe.
  module BurstPlan
    TEXTS = {
      "infinitepay" => [
        "minha maquininha não liga", "não recebi meu repasse de ontem", "quero aumentar meu limite de crédito",
        "o pix caiu duas vezes, cobraram R$ %<amount>d", "preciso de um empréstimo de R$ %<amount>d",
        "como emito a segunda via do boleto?", "quero falar com um atendente"
      ],
      "jim" => [
        "my card reader won't turn on", "where is my payout?", "I need a loan of US$ %<amount>d",
        "I was charged twice, $%<amount>d", "how do I update my bank account?", "I want to talk to a person"
      ]
    }.freeze
    CHANNELS = %w[app_chat whatsapp email].freeze

    module_function

    def build(count:, redeliver:, seed:, run: "s#{seed}")
      random = Random.new(seed)
      customers = [ (count * 0.6).ceil, 1 ].max
      keyed = []

      count.times do |index|
        customer = random.rand(customers)
        brand = customer % 10 < 7 ? "infinitepay" : "jim"
        item = {
          provider_message_id: "load-#{run}-#{index}",
          brand: brand,
          channel: CHANNELS[customer % CHANNELS.size],
          customer: "load-#{run}-c#{customer}",
          text: format(TEXTS.fetch(brand)[random.rand(TEXTS.fetch(brand).size)], amount: 100 + random.rand(20_000)),
          redelivery: false
        }
        keyed << [ index.to_f, item ]
        # A reentrega sai depois do original, de 0,5 a 20 posições mais tarde.
        keyed << [ index + 0.5 + random.rand * 20, item.merge(redelivery: true) ] if random.rand < redeliver
      end

      keyed.sort_by(&:first).map(&:last)
    end
  end
end
