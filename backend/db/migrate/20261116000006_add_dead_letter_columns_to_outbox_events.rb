class AddDeadLetterColumnsToOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :outbox_events, bulk: true do |t|
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      # Recusado de vez pelo broker: fica estacionado e retém os próximos eventos do mesmo ticket.
      t.timestamptz :dead_at
      # Estacionado que a operação decidiu não reenviar.
      t.timestamptz :discarded_at
    end
  end
end
