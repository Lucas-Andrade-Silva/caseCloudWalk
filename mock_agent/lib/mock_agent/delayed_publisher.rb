module MockAgent
  # Publica itens depois de um atraso, sem bloquear quem agenda. Uma única thread atende todos os itens,
  # em ordem de horário; com atrasos diferentes, as respostas saem fora da ordem de chegada (é o objetivo).
  class DelayedPublisher
    def initialize(&publish)
      @publish = publish
      @items = []
      @mutex = Mutex.new
      @wakeup = ConditionVariable.new
      @stopped = false
      @thread = Thread.new { run }
    end

    def schedule(delay_seconds, item)
      due = now + delay_seconds
      @mutex.synchronize do
        @items << [ due, item ]
        @items.sort_by!(&:first)
        @wakeup.signal
      end
    end

    def stop
      @mutex.synchronize do
        @stopped = true
        @wakeup.signal
      end
      @thread.join(2)
    end

    private

    def run
      loop do
        item = @mutex.synchronize { next_due_item }
        break if item.equal?(:stop)

        @publish.call(item)
      rescue StandardError => error
        MockAgent.logger.error("falha ao publicar resposta atrasada: #{error.class}: #{error.message}")
      end
    end

    # Espera (dentro do mutex) até o primeiro item vencer, ou até chegar um item mais urgente.
    def next_due_item
      loop do
        return :stop if @stopped

        if @items.empty?
          @wakeup.wait(@mutex)
        else
          wait = @items.first.first - now
          return @items.shift.last if wait <= 0

          @wakeup.wait(@mutex, wait)
        end
      end
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
