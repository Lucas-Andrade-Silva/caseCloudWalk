# Memória entre interações sem LLM (ADR 0006): resolução no fechamento, resumos de encerramento com prazo e
# exclusão da memória de um cliente com registro na auditoria.
class CreateCustomerMemory < ActiveRecord::Migration[8.1]
  RESOLUTION_CODES = %w[resolved no_customer_response duplicate forwarded].freeze

  def change
    change_table :tickets, bulk: true do |t|
      t.timestamptz :closed_at
      t.text :resolution_code
      t.text :resolution_note
    end
    add_check_constraint :tickets,
                         "resolution_code IS NULL OR resolution_code IN (#{RESOLUTION_CODES.map { |c| "'#{c}'" }.join(', ')})",
                         name: "tickets_resolution_code_valid"
    add_check_constraint :tickets, "char_length(resolution_note) <= 2000", name: "tickets_resolution_note_length"
    # Memória: tickets do cliente na marca, mais recentes primeiro.
    add_index :tickets, %i[brand_id customer_id created_at]

    # Corte da exclusão: a memória ignora o que foi aberto antes disso.
    add_column :customers, :memory_erased_at, :timestamptz

    create_table :closing_summaries, id: :uuid do |t|
      t.references :ticket, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.integer :version, null: false
      t.text :source, null: false
      t.text :text, null: false
      t.timestamptz :expires_at, null: false
      t.timestamps
    end

    # Auditoria da exclusão. Sem texto do cliente.
    create_table :memory_erasures, id: :uuid do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.references :requested_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.integer :summaries_deleted, null: false
      t.timestamptz :created_at, null: false
    end
  end
end
