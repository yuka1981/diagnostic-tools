Rails.application.routes.draw do
  devise_for :users

  # API routes
  namespace :api do
    resources :nodes, only: [] do
      collection do
        get :hostname_suggestions
        post :validate
      end
    end

    resources :server_products, only: [ :index ] do
      collection do
        get :search
      end
    end

    namespace :v1 do
      get "health", to: "health#show"
      post "inventory/push", to: "inventory#push"
      resources :benchmark_runs, only: [ :create, :update ]
      post "nodes/:id/heartbeat", to: "heartbeats#create"
      resources :profiling_runs, param: :uuid, only: [] do
        member do
          post :status
          post :complete
        end
      end
    end
  end

  # Dashboard
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Resource routes
  resources :api_keys, only: [ :index, :new, :create, :destroy ] do
    member do
      patch :revoke
    end
  end

  namespace :settings do
    resource :ssh_defaults, only: [ :show, :update ], controller: :ssh_defaults
    resource :agent, only: [ :show, :update ], controller: :agents
    resources :agent_releases do
      member do
        patch :deprecate
        patch :activate
        patch :recall
      end
      resources :binaries, only: %i[new create destroy], controller: "agent_binaries"
    end
    resources :server_products do
      collection do
        post :sync
      end
    end
  end

  resources :sites
  resources :rooms do
    collection do
      get :for_site
    end
  end
  resources :server_racks, path: "racks" do
    member do
      patch :update_layout
    end
  end
  resources :nodes do
    member do
      post :test_connection
      post :collect
    end
    resources :benchmark_runs, only: %i[index new create], controller: "nodes/benchmark_runs"
    resources :profiling_runs, only: %i[index show new create], controller: "nodes/profiling_runs" do
      member do
        get "artifacts/:artifact_id/download", action: :download_artifact, as: :download_artifact
      end
    end
    resource :network, only: [], controller: "nodes/network" do
      get :ib_details
    end
    resource :update, only: %i[new create], controller: "nodes/updates"
    collection do
      delete :bulk_destroy
      resources :imports, only: %i[new create], controller: "nodes/imports", as: :node_import
      resources :installs, only: %i[new create], controller: "nodes/installs", as: :node_install
      resources :uninstalls, only: %i[new create], controller: "nodes/uninstalls", as: :node_uninstall
    end
  end
  resources :benchmark_runs, only: %i[index show] do
    member do
      get "artifacts/:artifact_id/download", action: :download_artifact, as: :download_artifact
      post :cancel
    end
  end
  resources :benchmark_recipes do
    member do
      patch :archive
      patch :activate
    end
  end

  resources :mlc_benchmarks, only: %i[new create]

  resources :tasks, only: [ :index, :destroy ] do
    member do
      post :cancel
      post :rerun
    end
  end

  resources :notifications, only: [ :index ] do
    member do
      post :mark_read
    end
    collection do
      get :dropdown
      post :mark_all_read
      post :archive_read
    end
  end

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
