module Api
  module Agent
    # API que o agente de IA usa, por meio do broker, para responder num ticket como usuário bot.
    class RepliesController < ApplicationController
      before_action :authenticate_bot

      def create
        payload = parse_json(request.raw_post)
        result = ::Agent::RecordReply.call(
          agent_turn_id: payload["agent_turn_id"],
          ticket_id: payload["ticket_id"],
          in_reply_to_seq: payload["in_reply_to_seq"],
          handoff_epoch: payload["handoff_epoch"],
          action: payload["action"],
          text: payload["text"],
          reason: payload["reason"]
        )

        if result.status == :discarded
          render status: :conflict, json: { discarded: true, reason: result.reason }
        else
          duplicate = result.status == :duplicate
          render status: duplicate ? :ok : :created, json: body_for(result, duplicate)
        end
      rescue ::Agent::RecordReply::Invalid => error
        render status: :unprocessable_content, json: { error: error.message }
      rescue ::Agent::RecordReply::TicketNotFound
        render status: :not_found, json: { error: "ticket não encontrado" }
      end

      private

      def body_for(result, duplicate)
        message = result.message
        if result.escalated
          { escalated: true, duplicate: duplicate, message_id: message&.id, seq: message&.seq }
        else
          { message_id: message.id, seq: message.seq, stale: message.stale, duplicate: duplicate }
        end
      end

      def authenticate_bot
        token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
        user = User.find_by_token(token)

        if user.nil?
          render status: :unauthorized, json: { error: "token inválido" }
        elsif !user.bot?
          render status: :forbidden, json: { error: "apenas o usuário bot pode responder como agente" }
        end
      end

      def parse_json(body)
        parsed = JSON.parse(body)
        raise ::Agent::RecordReply::Invalid, "o corpo precisa ser um objeto JSON" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise ::Agent::RecordReply::Invalid, "o corpo não é JSON válido"
      end
    end
  end
end
