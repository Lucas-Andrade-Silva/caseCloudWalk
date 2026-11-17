module Api
  module Ops
    # Direito ao esquecimento: a operação apaga a memória de um cliente numa marca (ADR 0006, M4).
    class CustomerMemoriesController < BaseController
      def destroy
        brand = Brand.find_by(slug: params[:brand])
        customer = brand && Customer.find_by(brand: brand, external_id: params[:external_id])
        return render(status: :not_found, json: { error: "cliente não encontrado" }) unless customer

        deleted = Memory::Erase.call(customer: customer, requested_by: current_user)
        render json: { summaries_deleted: deleted }
      end
    end
  end
end
