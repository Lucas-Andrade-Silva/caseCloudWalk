# Quem age na plataforma. O agente de IA é um usuário de papel `bot`, com token próprio.
class User < ApplicationRecord
  ROLES = %w[customer analyst ops bot].freeze

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token)
    return if token.blank?

    find_by(token_digest: digest(token))
  end

  def bot? = role == "bot"
end
