module ApplicationCable
  # Conexão WebSocket do mapa vivo (ADR 0007, I13). O token vem no subprotocolo
  # `helpdesk-token.<token em base64url>`, nunca na URL, que acaba em logs de servidor e de proxy.
  class Connection < ActionCable::Connection::Base
    PROTOCOL_PREFIX = "helpdesk-token."
    PEOPLE = %w[analyst ops].freeze

    identified_by :current_user

    def connect
      self.current_user = find_person || reject_unauthorized_connection
    end

    private

    def find_person
      user = User.find_by_token(token_from_protocol)
      user if user && PEOPLE.include?(user.role)
    end

    def token_from_protocol
      offered = request.headers["Sec-WebSocket-Protocol"].to_s.split(",").map(&:strip)
      encoded = offered.find { |protocol| protocol.start_with?(PROTOCOL_PREFIX) }&.delete_prefix(PROTOCOL_PREFIX)
      return if encoded.blank?

      Base64.urlsafe_decode64(encoded)
    rescue ArgumentError
      nil
    end
  end
end
