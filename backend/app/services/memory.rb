# Memória entre interações (ADR 0006).
module Memory
  DEFAULT_WINDOW_DAYS = 90

  module_function

  # Janela da memória e prazo dos resumos, em dias (MEMORY_WINDOW_DAYS).
  def window_days
    Integer(ENV.fetch("MEMORY_WINDOW_DAYS", DEFAULT_WINDOW_DAYS))
  end
end
