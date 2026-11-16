class CreateProcessedEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_events, primary_key: %i[consumer_name event_id] do |t|
      t.text :consumer_name, null: false
      t.uuid :event_id, null: false
      t.timestamptz :processed_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
