class CreateTeamsRulesAndDecisions < ActiveRecord::Migration[8.1]
  def up
    # Equipe: grupo de analistas que é dono de filas (ADR 0005, R1).
    create_table :teams, id: :uuid do |t|
      t.text :slug, null: false, index: { unique: true }
      t.text :name, null: false
      t.timestamps
    end

    create_table :team_memberships, primary_key: %i[user_id team_id] do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: false
      t.references :team, type: :uuid, null: false, foreign_key: true
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_reference :queues, :team, type: :uuid, foreign_key: true

    # Os vínculos analista <-> fila da fatia 03 viram uma equipe por fila, com os mesmos analistas.
    # Ninguém passa a atender nem deixa de atender fila nenhuma.
    execute <<~SQL
      INSERT INTO teams (id, slug, name, created_at, updated_at)
        SELECT gen_random_uuid(), 'equipe-' || q.slug, 'Equipe ' || q.name, now(), now() FROM queues q;
      UPDATE queues q SET team_id = t.id FROM teams t WHERE t.slug = 'equipe-' || q.slug;
      INSERT INTO team_memberships (user_id, team_id)
        SELECT qm.user_id, q.team_id FROM queue_memberships qm JOIN queues q ON q.id = qm.queue_id;
    SQL
    change_column_null :queues, :team_id, false
    drop_table :queue_memberships

    add_column :tickets, :tags, :text, array: true, null: false, default: []

    # Conjunto de regras de uma marca. Cada versão guarda a lista inteira; publicada, não muda (R4).
    create_table :rule_sets, id: :uuid do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.integer :version, null: false
      t.text :status, null: false, default: "draft"
      t.jsonb :rules, null: false, default: []
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }, index: false
      t.timestamptz :published_at
      t.timestamps
      t.check_constraint "status IN ('draft', 'published', 'archived')", name: "rule_sets_status_valid"
      t.index %i[brand_id version], unique: true
      t.index :brand_id, unique: true, where: "status = 'published'", name: "index_rule_sets_one_published_per_brand"
    end

    # Auditoria de cada decisão de roteamento (R5). Append-only, sem o texto do cliente.
    create_table :decisions do |t|
      t.references :ticket, type: :uuid, null: false, foreign_key: true, index: false
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.text :step, null: false
      t.text :actor, null: false
      t.references :rule_set, type: :uuid, foreign_key: true, index: false
      t.integer :rule_set_version
      t.text :matched_rule_id
      t.jsonb :facts, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.index %i[ticket_id id]
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "os vínculos analista <-> fila foram convertidos em equipes"
  end
end
