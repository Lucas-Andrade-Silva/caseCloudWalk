Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Tempo real do mapa vivo (ADR 0007, I13).
  mount ActionCable.server => "/cable"

  # Entrada dos canais simulados.
  post "webhooks/channels/:channel", to: "webhooks/channels#create"

  # API do agente de IA (usuário bot), chamada pelo broker.
  namespace :api do
    namespace :agent do
      resources :replies, only: :create
    end

    # Quem está usando a interface.
    get "me", to: "me#show"

    # Mapa vivo: retrato inicial; os eventos chegam pelo ActionCable em /cable.
    get "map", to: "map#show"

    # Canal simulado do chat do cliente (só com CHANNEL_SIMULATOR_ENABLED=true).
    post "simulator/messages", to: "simulator#create"
    get "simulator/conversation", to: "simulator#conversation"

    # Modo Incidente (ADR 0009): incidentes abertos e "responder a todos".
    resources :incidents, only: :index do
      post :resolve, on: :member
    end

    # Analista humano.
    get "work", to: "work#index"
    post "work/next", to: "work#next"
    resources :tickets, only: :show do
      member do
        post :takeover
        post :messages
        post :close
      end
    end

    # Operação: equipes, filas e regras.
    namespace :ops do
      get "analysts", to: "support#analysts"
      get "rules/catalog", to: "support#rules_catalog"
      resources :teams, only: %i[index create]
      post "teams/:id/members", to: "teams#add_member"
      delete "teams/:id/members/:user_id", to: "teams#remove_member"
      resources :queues, only: %i[index create update]
      get "brands/:brand/rule_sets", to: "rule_sets#index"
      post "brands/:brand/rule_sets", to: "rule_sets#create"
      delete "brands/:brand/customers/:external_id/memory", to: "customer_memories#destroy",
                                                            constraints: { external_id: %r{[^/]+} }
      resources :rule_sets, only: %i[show update] do
        member do
          post :publish
          post :dry_run
        end
      end
    end
  end
end
