# Quem age na plataforma. O agente de IA é um usuário de papel `bot`, com token próprio.
class User < ApplicationRecord
  ROLES = %w[customer analyst ops bot].freeze

  has_many :queue_memberships
  has_many :queues, through: :queue_memberships

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token)
    return if token.blank?

    find_by(token_digest: digest(token))
  end

  def bot? = role == "bot"
  def analyst? = role == "analyst"

  # Marcas que o analista atende, pelas filas de que faz parte.
  def brand_ids = queues.distinct.pluck(:brand_id)
end
