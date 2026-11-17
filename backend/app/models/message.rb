class Message < ApplicationRecord
  SENDERS = %w[customer bot analyst system].freeze

  belongs_to :ticket
  belongs_to :brand
  belongs_to :inbound_event, optional: true
end
