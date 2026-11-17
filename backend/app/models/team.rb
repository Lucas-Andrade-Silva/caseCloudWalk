# Equipe: grupo de analistas que é dono de filas, de uma ou mais marcas (ADR 0005, R1).
class Team < ApplicationRecord
  has_many :team_memberships, dependent: :delete_all
  has_many :members, through: :team_memberships, source: :user
  has_many :queues, class_name: "TicketQueue"

  validates :slug, format: { with: /\A[a-z0-9-]{1,64}\z/ }, uniqueness: true
  validates :name, presence: true
end
