# Um atendimento: a conversa com o cliente e o estado de quem está atendendo.
# Ticket e conversa são a mesma entidade (ADR 0003, E2).
class Ticket < ApplicationRecord
  class InvalidTransition < StandardError; end

  CHANNELS = %w[app_chat whatsapp email].freeze
  MODES = %w[ai pending_human human closed].freeze

  # Máquina de estados do handoff (playbook §3.4). Não existe volta para a IA na primeira versão.
  TRANSITIONS = {
    "ai" => %w[pending_human human closed],
    "pending_human" => %w[human],
    "human" => %w[closed],
    "closed" => []
  }.freeze

  # Transições que trocam o dono do ticket. Cada troca incrementa o handoff_epoch, e o bot só escreve
  # com o epoch atual: resposta antiga não passa.
  OWNER_CHANGES = [ %w[ai pending_human], %w[ai human], %w[pending_human human] ].freeze

  belongs_to :brand
  belongs_to :customer
  belongs_to :queue, class_name: "TicketQueue", optional: true
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :priority_level, foreign_key: :priority, optional: true
  has_many :messages
  has_many :conversation_events
  has_one :closing_summary

  # Como o analista resolveu o ticket (ADR 0006, M2).
  RESOLUTION_CODES = %w[resolved no_customer_response duplicate forwarded].freeze
  RESOLUTION_NOTE_MAX = 2000

  scope :open, -> { where.not(mode: "closed") }

  def ai? = mode == "ai"
  def human? = mode == "human"

  # Muda o modo e, na mesma gravação, os atributos que acompanham a mudança.
  def transition_to!(target, **attributes)
    unless TRANSITIONS.fetch(mode).include?(target)
      raise InvalidTransition, "ticket #{id}: #{mode} -> #{target} não é permitido"
    end

    epoch = OWNER_CHANGES.include?([ mode, target ]) ? handoff_epoch + 1 : handoff_epoch
    update!(mode: target, handoff_epoch: epoch, **attributes)
  end

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

  # O agente respondeu até a mensagem `seq` do cliente. Se o cliente já mandou outra depois, a espera
  # passa a contar a partir dela; se não, ninguém espera o agente.
  def agent_answered_through!(seq)
    next_waiting = messages.where(sender: "customer").where("seq > ?", seq).order(:seq).first
    update!(awaiting_agent_since: next_waiting&.created_at)
  end
end
