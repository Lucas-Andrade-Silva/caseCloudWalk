require "openssl"

module Broker
  # Assinatura de webhook: HMAC-SHA256 sobre "id.timestamp.corpo", no formato "v1=<hex>".
  # É o mesmo contrato do lado da plataforma (docs/specs/02); cada lado tem a sua implementação
  # porque são serviços separados.
  module Signature
    VERSION = "v1"
    TOLERANCE = 300 # segundos

    module_function

    def sign(id:, timestamp:, body:, secret:)
      "#{VERSION}=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{id}.#{timestamp}.#{body}")}"
    end

    def valid?(id:, timestamp:, body:, signature:, secrets:, now: Time.now)
      return false if id.to_s.empty? || signature.to_s.empty?

      sent_at = Integer(timestamp.to_s, 10, exception: false)
      return false if sent_at.nil? || (now.to_i - sent_at).abs > TOLERANCE

      secrets.any? do |secret|
        expected = sign(id: id, timestamp: sent_at, body: body, secret: secret)
        expected.bytesize == signature.bytesize && OpenSSL.fixed_length_secure_compare(expected, signature)
      end
    end
  end
end
