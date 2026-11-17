class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_events do |t|
      t.uuid :event_id, null: false
      t.text :topic, null: false
      t.text :key, null: false
      t.jsonb :payload, null: false
      t.jsonb :headers, null: false, default: {}
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamptz :published_at
    end

    add_index :outbox_events, :event_id, unique: true
    # O relay só olha para o que falta publicar; o índice parcial fica pequeno mesmo com a tabela grande.
    add_index :outbox_events, :id, where: "published_at IS NULL", name: "index_outbox_events_pending"
  end
end
