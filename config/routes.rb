Rage.routes.draw do
  root to: "articles#index"
  resources :articles

  # The live session: one WebSocket connection per browser tab, handled by LiveChannel.
  mount Rage::Cable.application, at: "/live"
end
