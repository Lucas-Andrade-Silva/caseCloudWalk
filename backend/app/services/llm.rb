# LLM da plataforma (ADR 0002, D9; ADR 0008, L1 a L3; playbook §5). Fornece fatos e textos; nunca decide fila
# nem prioridade. Modos (LLM_MODE): off, stub (testes e carga), replay (respostas gravadas no repositório) e
# live (Groq). Testes e carga nunca chamam o Groq.
module Llm
  MODES = %w[off stub replay live].freeze

  module_function

  def mode
    value = ENV.fetch("LLM_MODE", "stub")
    MODES.include?(value) ? value : "off"
  end

  def api_key = ENV["GROQ_API_KEY"].presence
  def timeout_seconds = Float(ENV.fetch("LLM_TIMEOUT_SECONDS", "2"))
  def record? = ENV["LLM_RECORD"] == "true"
  def replay_dir = Rails.root.join("llm_replay")

  # Um disjuntor por processo: com o Groq fora, as chamadas param de esperar timeout uma atrás da outra.
  def breaker = @breaker ||= CircuitBreaker.new(threshold: 5, cooldown: 30)

  def client = Client.new
end
