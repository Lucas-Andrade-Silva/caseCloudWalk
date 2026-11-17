# Uma versão das regras de roteamento de uma marca (ADR 0002, D4; ADR 0005, R4).
# Nasce rascunho e pode ser editada; publicada, fica imutável. Publicar arquiva a anterior.
class RuleSet < ApplicationRecord
  class Immutable < StandardError; end

  belongs_to :brand
  belongs_to :created_by, class_name: "User", optional: true

  validate :rules_are_valid
  before_update :forbid_rule_changes_after_publish

  scope :newest_first, -> { order(version: :desc) }

  def self.published_for(brand) = find_by(brand: brand, status: "published")

  def draft? = status == "draft"

  def publish!
    raise Immutable, "a versão #{version} não é rascunho" unless draft?

    transaction do
      RuleSet.where(brand_id: brand_id, status: "published").where.not(id: id).update_all(status: "archived")
      update!(status: "published", published_at: Time.current)
    end
  end

  def validation_errors = Rules::Validator.errors(rules, brand: brand)

  private

  def rules_are_valid
    validation_errors.each { |error| errors.add(:rules, "#{error[:path]}: #{error[:message]}") }
  end

  def forbid_rule_changes_after_publish
    return if status_in_database == "draft"

    raise Immutable, "a versão #{version} já foi publicada e não muda" if will_save_change_to_rules?
  end
end
