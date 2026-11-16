class CreateDomainCore < ActiveRecord::Migration[8.1]
  def change
    create_table :brands, id: :uuid do |t|
      t.text :slug, null: false, index: { unique: true }
      t.text :name, null: false
      t.timestamps
    end

    create_table :users, id: :uuid do |t|
      t.text :name, null: false
      t.text :role, null: false
      # Só o hash do token fica no banco.
      t.text :token_digest, null: false, index: { unique: true }
      t.timestamps
      t.check_constraint "role IN ('customer', 'analyst', 'ops', 'bot')", name: "users_role_valid"
    end

    create_table :customers, id: :uuid do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.text :external_id, null: false
      t.text :name
      t.timestamps
      t.index %i[brand_id external_id], unique: true
    end

    # Ticket e conversa são a mesma entidade (ADR 0003, E2).
    create_table :tickets, id: :uuid do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: false
      t.text :channel, null: false
      t.text :mode, null: false, default: "ai"
      t.integer :handoff_epoch, null: false, default: 0
      t.integer :last_seq, null: false, default: 0
      t.timestamps
      t.check_constraint "channel IN ('app_chat', 'whatsapp', 'email')", name: "tickets_channel_valid"
      t.check_constraint "mode IN ('ai', 'pending_human', 'human', 'closed')", name: "tickets_mode_valid"
      # No máximo um ticket aberto por cliente, marca e canal. O banco decide a disputa entre
      # duas primeiras mensagens simultâneas.
      t.index %i[brand_id customer_id channel], unique: true, where: "mode <> 'closed'",
                                                name: "index_tickets_one_open_per_customer_channel"
    end

    create_table :inbound_events do |t|
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.text :channel, null: false
      t.text :provider_message_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamptz :received_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      # Dedupe de webhook: a mesma mensagem do provedor só entra uma vez.
      t.index %i[channel provider_message_id], unique: true
    end

    create_table :messages, id: :uuid do |t|
      t.references :ticket, type: :uuid, null: false, foreign_key: true, index: false
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.references :inbound_event, foreign_key: true, index: { unique: true }
      t.integer :seq, null: false
      t.text :sender, null: false
      t.text :body, null: false
      t.integer :in_reply_to_seq
      t.uuid :agent_turn_id, index: { unique: true }
      t.boolean :stale, null: false, default: false
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.check_constraint "sender IN ('customer', 'bot', 'analyst', 'system')", name: "messages_sender_valid"
      t.index %i[ticket_id seq], unique: true
    end

    # Linha do tempo append-only: auditoria, histórico e verificação de invariantes.
    create_table :conversation_events do |t|
      t.references :ticket, type: :uuid, null: false, foreign_key: true, index: false
      t.references :brand, type: :uuid, null: false, foreign_key: true, index: false
      t.text :kind, null: false
      t.text :actor, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.index %i[ticket_id id]
    end
  end
end
