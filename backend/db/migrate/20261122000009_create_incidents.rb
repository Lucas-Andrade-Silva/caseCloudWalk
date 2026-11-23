# Modo Incidente (ADR 0009, W1 e W2): um pico de tickets parecidos vira um incidente que agrupa os tickets.
# No máximo um incidente aberto por marca e chave (índice parcial único): detecções concorrentes acham o mesmo.
class CreateIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :incidents, id: :uuid do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.string :label, null: false
      t.string :status, null: false, default: "open"
      t.string :title, null: false
      t.text :draft_reply, null: false
      t.string :title_source, null: false, default: "template"
      t.string :prompt_version
      t.string :model
      t.datetime :opened_at, null: false
      t.datetime :resolved_at
      t.references :resolved_by, type: :uuid, foreign_key: { to_table: :users }, index: false
      t.timestamps
    end
    add_index :incidents, %i[brand_id key], unique: true, where: "status = 'open'", name: "index_incidents_open_by_key"
    add_index :incidents, %i[brand_id status opened_at]
    add_check_constraint :incidents, "status IN ('open', 'resolved')", name: "incidents_status_check"

    add_reference :tickets, :incident, type: :uuid, foreign_key: true, index: true
  end
end
