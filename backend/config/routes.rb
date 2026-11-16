Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Entrada dos canais simulados.
  post "webhooks/channels/:channel", to: "webhooks/channels#create"

  # API do agente de IA (usuário bot), chamada pelo broker.
  namespace :api do
    namespace :agent do
      resources :replies, only: :create
    end
  end
end
