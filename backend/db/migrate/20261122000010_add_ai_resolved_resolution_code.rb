# Ticket resolvido pela IA fecha sozinho depois de um tempo sem mensagem do cliente (ADR 0009, W4), com um código
# de resolução próprio. O analista não escolhe esse código: ele só existe no fechamento automático.
class AddAiResolvedResolutionCode < ActiveRecord::Migration[8.1]
  OLD = %w[resolved no_customer_response duplicate forwarded].freeze
  NEW = (OLD + %w[ai_resolved]).freeze

  def up
    remove_check_constraint :tickets, name: "tickets_resolution_code_valid"
    add_check_constraint :tickets, check(NEW), name: "tickets_resolution_code_valid"
  end

  def down
    remove_check_constraint :tickets, name: "tickets_resolution_code_valid"
    add_check_constraint :tickets, check(OLD), name: "tickets_resolution_code_valid"
  end

  private

  def check(codes) = "resolution_code IS NULL OR resolution_code IN (#{codes.map { |code| "'#{code}'" }.join(', ')})"
end
