require "net/http"

module Llm
  # Adaptador único do LLM (ADR 0002, D9; playbook §5). Nada aqui levanta exceção: devolve um Result, e quem
  # chama segue sem LLM quando `ok` é falso (fallback para regras e templates).
  #
  # Sempre: redige dados pessoais, põe o texto do cliente entre delimitadores, pede saída no schema estrito,
  # confere o schema na volta e registra modelo e versão do prompt.
  class Client
    Result = Data.define(:ok, :data, :source, :error, :prompt_version, :model, :key)

    GROQ_URL = URI("https://api.groq.com/openai/v1/chat/completions")

    def initialize(mode: Llm.mode, transport: nil, replay_dir: Llm.replay_dir, api_key: Llm.api_key,
                   record: Llm.record?, breaker: Llm.breaker, timeout: Llm.timeout_seconds)
      @mode = mode
      @transport = transport || method(:post_to_groq)
      @replay_dir = Pathname(replay_dir)
      @api_key = api_key
      @record = record
      @breaker = breaker
      @timeout = timeout
    end

    def call(task:, input:)
      prompt = Prompt.load(task)
      return failure(prompt, "disabled") if @mode == "off"

      redacted = Redactor.call(input).text
      key = Digest::SHA256.hexdigest([ prompt.version, prompt.model, redacted ].join("\n"))
      data, source, error = answer(prompt, redacted, key)
      return failure(prompt, error, key) if error
      return failure(prompt, "invalid_output", key) unless Schema.valid?(prompt.schema, data)

      save_replay(prompt, key, data) if @record && source == "live"
      Result.new(ok: true, data: data, source: source, error: nil, prompt_version: prompt.version, model: prompt.model, key: key)
    end

    private

    def answer(prompt, redacted, key)
      case @mode
      when "stub" then stub(prompt, redacted)
      when "replay" then replay(prompt, key)
      when "live" then live(prompt, redacted)
      end
    end

    def stub(prompt, redacted)
      [ Stub.respond(prompt.task, redacted), "stub", nil ]
    rescue Stub::InjectedFailure
      [ nil, "stub", "stub_failure" ]
    end

    def replay(prompt, key)
      file = @replay_dir.join(prompt.task, "#{key}.json")
      return [ nil, "replay", "replay_miss" ] unless file.exist?

      [ JSON.parse(file.read).fetch("data"), "replay", nil ]
    end

    def live(prompt, redacted)
      return [ nil, "live", "missing_api_key" ] unless @api_key
      return [ nil, "live", "circuit_open" ] if @breaker.open?

      response = @transport.call(request_body(prompt, redacted))
      @breaker.success!
      [ parse_content(response), "live", nil ]
    rescue StandardError => error
      @breaker.failure!
      [ nil, "live", error.class.name ]
    end

    def request_body(prompt, redacted)
      {
        "model" => prompt.model,
        "temperature" => prompt.temperature,
        "max_tokens" => prompt.max_tokens,
        "messages" => [
          { "role" => "system", "content" => prompt.system },
          # O texto do cliente é dado, nunca instrução (playbook §5).
          { "role" => "user", "content" => "<mensagem>\n#{redacted}\n</mensagem>" }
        ],
        "response_format" => {
          "type" => "json_schema",
          "json_schema" => { "name" => prompt.task, "schema" => prompt.schema, "strict" => true }
        }
      }
    end

    def parse_content(response)
      JSON.parse(response.dig("choices", 0, "message", "content").to_s)
    rescue JSON::ParserError
      nil
    end

    def save_replay(prompt, key, data)
      file = @replay_dir.join(prompt.task, "#{key}.json")
      FileUtils.mkdir_p(file.dirname)
      file.write(JSON.pretty_generate("prompt_version" => prompt.version, "model" => prompt.model, "data" => data) + "\n")
    end

    def failure(prompt, error, key = nil)
      Result.new(ok: false, data: nil, source: @mode, error: error, prompt_version: prompt.version, model: prompt.model, key: key)
    end

    def post_to_groq(body)
      Net::HTTP.start(GROQ_URL.host, GROQ_URL.port, use_ssl: true, open_timeout: @timeout, read_timeout: @timeout) do |http|
        response = http.post(GROQ_URL.path, body.to_json,
                             "Content-Type" => "application/json", "Authorization" => "Bearer #{@api_key}")
        raise "Groq respondeu #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end
    end
  end
end
