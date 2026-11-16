module Api
  module Ops
    # Base da API de operação: quem configura equipes, filas e regras sem depender de desenvolvimento.
    class BaseController < ApplicationController
      before_action :authenticate_ops

      private

      attr_reader :current_user

      def authenticate_ops
        token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
        user = User.find_by_token(token)

        if user.nil?
          render status: :unauthorized, json: { error: "token inválido" }
        elsif user.role != "ops"
          render status: :forbidden, json: { error: "apenas a operação" }
        else
          @current_user = user
        end
      end

      def body
        @body ||= begin
          parsed = JSON.parse(request.raw_post.presence || "{}")
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end
      end

      def unprocessable(errors)
        render status: :unprocessable_content, json: { errors: Array(errors) }
      end

      def record_errors(record)
        record.errors.map { |error| { path: error.attribute.to_s, message: error.message } }
      end
    end
  end
end
