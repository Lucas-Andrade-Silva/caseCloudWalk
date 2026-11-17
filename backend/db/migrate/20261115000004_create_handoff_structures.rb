class CreateHandoffStructures < ActiveRecord::Migration[8.1]
  def change
    # Níveis de prioridade com o prazo da primeira resposta humana (ADR 0004, H3). Editáveis.
    create_table :priority_levels, id: false do |t|
      t.text :code, primary_key: true
      t.text :name, null: false
      t.integer :first_response_minutes, null: false
      t.integer :position, null: false
      t.check_constraint "first_response_minutes > 0", name: "priority_levels_minutes_positive"
    end

    create_table :queues, id: :uuid do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true
      t.text :slug, null: false, index: { unique: true }
      t.text :name, null: false
      t.boolean :default, null: false, default: false
      t.timestamps
      # Uma fila padrão por marca: o destino do ticket escalado quando nenhuma regra decide (H2).
      t.index :brand_id, unique: true, where: '"default"', name: "index_queues_one_default_per_brand"
    end

    create_table :queue_memberships, primary_key: %i[user_id queue_id] do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: false
      t.references :queue, type: :uuid, null: false, foreign_key: true
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    change_table :tickets do |t|
      t.references :queue, type: :uuid, foreign_key: true, index: false
      t.text :priority, null: false, default: "p3"
      t.references :assignee, type: :uuid, foreign_key: { to_table: :users }
      # Lock otimista do Active Record: atualizar uma cópia velha do ticket falha em vez de sobrescrever.
      t.integer :lock_version, null: false, default: 0
      t.text :escalation_trigger
      t.text :escalation_reason
      t.timestamptz :escalated_at
      t.timestamptz :first_response_due_at
      t.timestamptz :first_human_response_at
      t.jsonb :handoff_brief
      # Desde quando o cliente espera o agente responder (nulo quando não há nada pendente).
      t.timestamptz :awaiting_agent_since
    end

    # Os tickets que já existem recebem `p3`; o nível precisa existir antes da chave estrangeira.
    # Os valores repetem PriorityLevel::DEFAULTS de propósito: migração não depende de modelo.
    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO priority_levels (code, name, first_response_minutes, position) VALUES
            ('p1', 'urgente', 5, 1), ('p2', 'alta', 15, 2), ('p3', 'normal', 60, 3), ('p4', 'baixa', 240, 4)
          ON CONFLICT (code) DO NOTHING
        SQL
      end
    end
    add_foreign_key :tickets, :priority_levels, column: :priority, primary_key: :code

    # Fila de escalados: "pegar o próximo" ordena pelo prazo mais próximo.
    add_index :tickets, %i[queue_id first_response_due_at], where: "mode = 'pending_human' AND assignee_id IS NULL",
                                                             name: "index_tickets_waiting_for_human"
    # Vigia do agente: só olha tickets com a IA que têm cliente esperando.
    add_index :tickets, :awaiting_agent_since, where: "mode = 'ai' AND awaiting_agent_since IS NOT NULL",
                                               name: "index_tickets_awaiting_agent"
  end
end
