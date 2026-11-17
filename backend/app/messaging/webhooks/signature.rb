module Webhooks
  # Assinatura de webhook, usada nos dois sentidos (canal -> plataforma e plataforma -> broker).
  #
  # O texto assinado é "id.timestamp.corpo". O timestamp entra na assinatura para que uma
  # requisição capturada não possa ser reenviada depois da janela de tolerância.
  module Signature
    VERSION = "v1"
    TOLERANCE = 300 # segundos

    module_function

    def sign(id:, timestamp:, body:, secret:)
      "#{VERSION}=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{id}.#{timestamp}.#{body}")}"
    end

    # Verdadeiro se a assinatura confere com algum dos segredos e o timestamp está na tolerância.
    def valid?(id:, timestamp:, body:, signature:, secrets:, now: Time.now)
      return false if id.blank? || signature.blank?

      sent_at = Integer(timestamp.to_s, 10, exception: false)
      return false if sent_at.nil? || (now.to_i - sent_at).abs > TOLERANCE

      secrets.any? do |secret|
        expected = sign(id: id, timestamp: sent_at, body: body, secret: secret)
        ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
      end
    end
  end
end
