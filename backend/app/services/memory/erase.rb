module Memory
  # Apaga a memória de um cliente numa marca (ADR 0006, M4): os resumos de encerramento saem e a memória passa
  # a ignorar o que foi aberto antes de agora. Tickets e mensagens ficam (registro operacional e de auditoria).
  # A exclusão é registrada sem texto do cliente.
  module Erase
    module_function

    def call(customer:, requested_by:, now: Time.current)
      ApplicationRecord.transaction do
        deleted = ClosingSummary.where(customer_id: customer.id).delete_all
        customer.update!(memory_erased_at: now)
        MemoryErasure.create!(brand_id: customer.brand_id, customer: customer, requested_by: requested_by,
                              summaries_deleted: deleted, created_at: now)
        deleted
      end
    end
  end
end
