module Api
  module Ops
    # Versões das regras de roteamento de uma marca: rascunho, dry-run e publicação (ADR 0002, D4).
    class RuleSetsController < BaseController
      before_action :load_rule_set, only: %i[show update publish dry_run]

      def index
        brand = Brand.find_by(slug: params[:brand]) or return not_found("marca")
        render json: RuleSet.where(brand: brand).newest_first.map { |rule_set| summary(rule_set) }
      end

      def create
        brand = Brand.find_by(slug: params[:brand]) or return not_found("marca")
        rules = body["rules"]
        errors = Rules::Validator.errors(rules, brand: brand)
        return unprocessable(errors) if errors.any?

        rule_set = RuleSet.transaction do
          # Trava a marca para dois rascunhos simultâneos não pegarem o mesmo número de versão.
          brand.lock!
          version = (RuleSet.where(brand: brand).maximum(:version) || 0) + 1
          RuleSet.create!(brand: brand, version: version, rules: rules, created_by: current_user)
        end
        render status: :created, json: detail(rule_set)
      end

      def show
        render json: detail(@rule_set)
      end

      def update
        return conflict unless @rule_set.draft?

        errors = Rules::Validator.errors(body["rules"], brand: @rule_set.brand)
        return unprocessable(errors) if errors.any?

        @rule_set.update!(rules: body["rules"])
        render json: detail(@rule_set)
      end

      def publish
        return conflict unless @rule_set.draft?

        @rule_set.publish!
        render json: detail(@rule_set)
      end

      def dry_run
        limit = Integer(body.fetch("limit", 200), exception: false) || 200
        render json: Rules::DryRun.call(candidate: @rule_set, limit: limit)
      end

      private

      def load_rule_set
        @rule_set = RuleSet.find_by(id: params[:id]) or not_found("versão")
      end

      def not_found(what) = render(status: :not_found, json: { error: "#{what} não encontrada" })

      def conflict
        render status: :conflict, json: { error: "só um rascunho pode ser editado ou publicado" }
      end

      def summary(rule_set)
        { id: rule_set.id, brand: rule_set.brand.slug, version: rule_set.version, status: rule_set.status,
          published_at: rule_set.published_at&.iso8601(3), rules_count: rule_set.rules.size }
      end

      def detail(rule_set) = summary(rule_set).merge(rules: rule_set.rules)
    end
  end
end
