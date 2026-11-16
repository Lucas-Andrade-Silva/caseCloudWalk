# Registro bruto de cada webhook de canal aceito. O índice único em (channel, provider_message_id)
# é o dedupe de entrada.
class InboundEvent < ApplicationRecord
  belongs_to :brand
  has_one :message
end
