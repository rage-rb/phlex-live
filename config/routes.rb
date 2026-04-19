Rage.routes.draw do
  root to: "articles#index"
  resources :articles

  get "/live", to: "live#index"
end
