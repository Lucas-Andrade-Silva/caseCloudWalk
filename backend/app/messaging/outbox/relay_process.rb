module Outbox
  # Laço de longa duração do relay (serviço `relay` do Compose).
  #
  # - Só publica enquanto segura o SingleInstanceLock. O lock é reconfirmado a cada volta, porque
  #   uma reconexão silenciosa ao banco abriria uma sessão nova, sem o lock.
  # - Falha de publicação (Kafka fora, banco fora) não derruba o processo: registra o erro e tenta
  #   de novo com espera exponencial, jitter e teto.
  class RelayProcess
    IDLE_PAUSE = 0.2      # outbox vazio: quanto esperar antes de olhar de novo (segundos)
    STANDBY_PAUSE = 2.0   # outro relay está ativo: quanto esperar antes de tentar assumir
    MAX_BACKOFF = 30.0

    def initialize(relay: Relay.new,
                   lock_factory: ->(connection) { SingleInstanceLock.new(connection) },
                   sleeper: Kernel.method(:sleep),
                   logger: Rails.logger,
                   random: Random.new)
      @relay = relay
      @lock_factory = lock_factory
      @sleeper = sleeper
      @logger = logger
      @random = random
      @stopped = false
      @failures = 0
    end

    def run
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        lock = @lock_factory.call(connection)
        begin
          tick(lock) until @stopped
        ensure
          lock.release
        end
      end
    end

    # Só altera uma flag: pode ser chamado de dentro de um handler de sinal.
    def stop
      @stopped = true
    end

    private

    def tick(lock)
      return @sleeper.call(STANDBY_PAUSE) unless lock.acquire

      published = @relay.publish_pending
      @failures = 0
      @sleeper.call(IDLE_PAUSE) if published.zero?
    rescue StandardError => error
      @failures += 1
      @logger.error("[outbox relay] falha ##{@failures}: #{error.class}: #{error.message}")
      @sleeper.call(backoff)
    end

    def backoff
      ceiling = [ MAX_BACKOFF, 2.0**(@failures - 1) ].min
      ceiling * @random.rand(0.5..1.0)
    end
  end
end
