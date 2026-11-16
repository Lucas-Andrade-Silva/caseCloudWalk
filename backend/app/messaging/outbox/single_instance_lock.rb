module Outbox
  # Garante um único relay ativo. Dois relays publicando ao mesmo tempo quebrariam a ordem.
  #
  # Usa um advisory lock de sessão do Postgres: ele pertence à conexão e é solto pelo próprio
  # banco se o processo morrer, então não existe lock órfão para limpar.
  class SingleInstanceLock
    # Identificador arbitrário e fixo do lock do relay ("outbox" em ASCII).
    KEY = 0x6F7574626F78

    def initialize(connection, key: KEY)
      @connection = connection
      @key = Integer(key)
    end

    def acquire
      @connection.select_value("SELECT pg_try_advisory_lock(#{@key})")
    end

    def release
      @connection.select_value("SELECT pg_advisory_unlock(#{@key})")
    end
  end
end
