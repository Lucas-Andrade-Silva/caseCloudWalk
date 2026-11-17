module Api
  module Ops
    # Dados de apoio às telas da operação (ADR 0007, I10 e I11).
    class SupportController < BaseController
      def analysts
        analysts = User.where(role: "analyst").includes(:teams).order(:name)
        render json: analysts.map { |user| { id: user.id, name: user.name, teams: user.teams.map(&:slug).sort } }
      end

      # Fatos e operadores que as regras aceitam: a tela monta as listas daqui, sem cópia própria.
      def rules_catalog
        render json: { facts: Rules::Catalog::FACTS, operators: Rules::Catalog::OPERATORS }
      end
    end
  end
end
