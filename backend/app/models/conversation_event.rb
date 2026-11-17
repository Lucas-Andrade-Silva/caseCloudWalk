# Linha do tempo de um ticket. Só cresce: cada fato relevante (mensagem, decisão, descarte) vira uma
# linha, e nenhuma linha muda depois de gravada.
class ConversationEvent < ApplicationRecord
  belongs_to :ticket
  belongs_to :brand

  def readonly? = persisted?
end
