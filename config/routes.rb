Rails.application.routes.draw do
  # Vietnamese (the default locale) has no prefix; English pages live under /en.
  scope "(:locale)", locale: /en/ do
    # The custom controllers only add rate limits; the views stay in app/views/devise.
    devise_for :users, controllers: { sessions: "users/sessions", registrations: "users/registrations",
                                      passwords: "users/passwords", confirmations: "users/confirmations" }

    # "Tải dữ liệu của tôi" on the account page.
    resource :account_data, only: :create, path: "account/data", controller: "accounts/data_exports"

    resources :bookings, only: %i[index show new create], param: :code do
      member do
        patch :cancel
        # Moving a booking: the schedule in reschedule mode sends the new slot here to confirm it.
        get :reschedule, action: :review_reschedule
        patch :reschedule
      end
      delete :release_hold, on: :collection
    end

    # The owner's area. /admin is the day board; ?date=YYYY-MM-DD picks the day.
    namespace :admin do
      root "boards#show"
      resources :bookings, only: %i[show new create], param: :code do
        member do
          patch :check_in
          patch :no_show
          patch :mark_paid
          patch :cancel
          patch :undo_check_in
          patch :undo_no_show
          patch :undo_payment
          get :edit_schedule
          patch :reschedule
          patch :confirm_payment
          patch :cancel_venue_fault
          patch :mark_refunded
        end
      end
      resources :customers, only: %i[index show update], param: :phone
      # Regular customers' weekly bookings: new -> preview (every session checked) -> create.
      resources :series, only: %i[index new create show] do
        post :preview, on: :collection
        member do
          post :extend
          post :end_from
          post :close_range
          post :mark_paid
          post :request_payment
          patch :update_price
        end
      end
      resources :series_requests, only: [] do
        patch :decline, on: :member
      end
      resources :products, except: %i[show destroy]
      resources :vouchers, except: %i[show destroy]
      resources :packages, except: %i[show destroy]
      resources :announcements, except: :show
      resources :reviews, only: :index
      get "reports", to: "reports#show", as: :reports
      resources :bank_transactions, path: "transactions", only: %i[index update] do
        patch :assign, on: :member
      end
      resources :price_rules, except: :show
      resources :users, only: :destroy do
        member do
          patch :unlock_booking
          patch :cancel_deletion
        end
      end
      resource :settings, only: %i[edit update]
      resources :staff_members, path: "staff", only: %i[index create destroy]
    end

    get "privacy", to: "pages#privacy"
    resources :payments, only: :show, param: :token do
      get :qr, on: :member
    end

    # The home page is the booking schedule; ?date=YYYY-MM-DD picks the day.
    root "schedules#show"
  end

  # Bank transfers reported by SePay (no locale, no session; authenticated by API key).
  post "webhooks/sepay", to: "webhooks/sepay#create", as: :sepay_webhook

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  # The customer mobile app (Api::V1). No locale prefix: the language comes from Accept-Language.
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resource :registration, only: :create
      resource :account, only: %i[show update destroy] do
        post :export
        post :resend_verification
        resource :avatar, only: %i[update destroy]
      end
      resource :venue, only: :show
      resource :schedule, only: :show
      resource :hold, only: %i[create destroy]
      resources :bookings, only: %i[index show create], param: :code do
        member do
          patch :cancel
          # The new slot is checked and priced first (GET), then moved to (PATCH).
          get :reschedule, action: :review_reschedule
          patch :reschedule
          post :review
        end
      end
      resources :payments, only: :show, param: :token
      resource :quote, only: :create
      resources :packages, only: :index do
        post :buy, on: :member
      end
      resources :announcements, only: :index
      resources :waitlist_entries, path: "waitlist", only: %i[index create destroy]
      resources :series_requests, only: %i[index create destroy]
      resources :series, only: :index do
        # A transfer code for a month (YYYY-MM) still to pay.
        post :pay, on: :member
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
