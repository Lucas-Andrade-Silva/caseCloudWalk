module Llm
  # Disjuntor simples (playbook §5): depois de `threshold` falhas seguidas, fica aberto por `cooldown` segundos
  # e as chamadas voltam na hora para o caminho sem LLM. Um sucesso fecha de novo.
  class CircuitBreaker
    def initialize(threshold:, cooldown:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @threshold = threshold
      @cooldown = cooldown
      @clock = clock
      @failures = 0
      @opened_at = nil
      @mutex = Mutex.new
    end

    def open?
      @mutex.synchronize { @opened_at && @clock.call - @opened_at < @cooldown }
    end

    def success!
      @mutex.synchronize do
        @failures = 0
        @opened_at = nil
      end
    end

    def failure!
      @mutex.synchronize do
        @failures += 1
        @opened_at = @clock.call if @failures >= @threshold
      end
    end
  end
end
