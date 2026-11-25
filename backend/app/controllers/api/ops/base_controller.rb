module Api
  module Ops
    # Base da API de operação: quem configura equipes, filas e regras sem depender de desenvolvimento.
    class BaseController < ApplicationController
      include TokenAuthentication
      include JsonBody

      authenticate_roles "ops", forbidden: "apenas a operação"

      private

      def body = json_body

      def unprocessable(errors)
        render status: :unprocessable_content, json: { errors: Array(errors) }
      end

      def record_errors(record)
        record.errors.map { |error| { path: error.attribute.to_s, message: error.message } }
      end
    end
  end
end
