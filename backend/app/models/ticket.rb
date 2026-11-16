# Um atendimento: a conversa com o cliente e o estado de quem está atendendo.
# Ticket e conversa são a mesma entidade (ADR 0003, E2).
class Ticket < ApplicationRecord
  CHANNELS = %w[app_chat whatsapp email].freeze
  MODES = %w[ai pending_human human closed].freeze

  belongs_to :brand
  belongs_to :customer
  has_many :messages
  has_many :conversation_events

  scope :open, -> { where.not(mode: "closed") }

  def ai? = mode == "ai"

  # Acrescenta uma mensagem com o próximo seq. O lock de linha serializa os escritores do ticket,
  # então o seq não tem buraco nem repetição e a ordem de gravação é a ordem do seq.
  def append_message!(**attributes)
    with_lock do
      seq = last_seq + 1
      update!(last_seq: seq)
      messages.create!(brand_id: brand_id, seq: seq, **attributes)
    end
  end

  def record_event!(kind:, actor:, data: {})
    conversation_events.create!(brand_id: brand_id, kind: kind, actor: actor, data: data)
  end

  def last_customer_seq
    messages.where(sender: "customer").maximum(:seq)
  end
end
