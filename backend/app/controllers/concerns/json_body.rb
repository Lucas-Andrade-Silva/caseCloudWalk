# Corpo JSON tolerante das rotas de interface: vazio, inválido ou não-objeto vira {}.
module JsonBody
  extend ActiveSupport::Concern

  private

  def json_body
    @json_body ||= begin
      parsed = JSON.parse(request.raw_post.presence || "{}")
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
