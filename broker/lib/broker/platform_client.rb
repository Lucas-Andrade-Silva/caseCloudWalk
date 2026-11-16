require "net/http"
require "uri"

module Broker
  # Cliente HTTP da API da plataforma. O broker age em nome do agente de IA, com o token do bot.
  class PlatformClient
    REPLIES_PATH = "/api/agent/replies"
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 10

    def initialize(base_url: Config.platform_url, token: Config.bot_api_token, transport: method(:post))
      @uri = URI.join(base_url, REPLIES_PATH)
      @token = token
      @transport = transport
    end

    # Envia a resposta do agente e devolve o status HTTP da plataforma.
    def post_reply(json_body)
      headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
      @transport.call(@uri, headers, json_body)
    end

    private

    def post(uri, headers, body)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.post(uri.request_uri, body, headers).code.to_i
      end
    end
  end
end
