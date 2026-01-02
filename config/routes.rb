Rails.application.routes.draw do
  devise_for :users

  # API routes
  namespace :api do
    namespace :v1 do
      post "inventory/push", to: "inventory#push"
    end
  end

  # Dashboard
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Resource routes
  resources :nodes do
    collection do
      get "import/new", to: "nodes/imports#new", as: :new_import
      post "import", to: "nodes/imports#create", as: :import
    end
  end
  resources :benchmark_runs, only: %i[index show]
  resources :benchmark_recipes, only: %i[index show]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  root "dashboard#index"
end
