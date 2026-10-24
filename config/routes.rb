Rails.application.routes.draw do
  # Vietnamese (the default locale) has no prefix; English pages live under /en.
  scope "(:locale)", locale: /en/ do
    # The custom controllers only add rate limits; the views stay in app/views/devise.
    devise_for :users, controllers: { sessions: "users/sessions", registrations: "users/registrations",
                                      passwords: "users/passwords", confirmations: "users/confirmations" }
    # "Sign in with Google": Google's button posts its ID token; someone new then gives a phone number (AP-05).
    resource :google_sign_in, only: %i[new create], path: "users/google", controller: "users/google" do
      post :register
    end

    # "Tải dữ liệu của tôi" on the account page.
    resource :account_data, only: :create, path: "account/data", controller: "accounts/data_exports"

    resources :bookings, only: %i[index show new create], param: :code do
      member do
        patch :cancel
        # Moving a booking: the schedule in reschedule mode sends the new slot here to confirm it.
        get :reschedule, action: :review_reschedule
        patch :reschedule
        post :review
      end
      collection do
        delete :release_hold
        # The confirmation page's total, re-rendered when extras or the voucher code change.
        get :quote
      end
    end

    # Open play (giao lưu): the list is public; buying places leads to the payment page.
    resources :play_sessions, only: :index do
      post :buy, on: :member
    end
    resources :play_session_tickets, only: :destroy

    # The customers' own tournaments (a tool for their group, the venue takes no part): the list of the ones they
    # run; each one's page is open to anyone with its link (/tournaments/<share token>).
    resources :tournaments, param: :token do
      member do
        post :draw
        delete :draw, action: :undo_draw
        # The bookings it is played on (booking_ids[]).
        patch :bookings, action: :link_bookings
        # The organizer link: the page to accept it, accepting, a new link, removing an organizer (?user_id=).
        get "organize/:organizer_token", action: :organize, as: :organize
        post "organize/:organizer_token", action: :join
        patch :organizer_link, action: :reset_organizer_link
        delete :organizers, action: :remove_organizer
      end
      # Players typed one per line (create), a seed or a name (update), removing one.
      resources :entries, only: %i[create update destroy], controller: :tournament_entries
      # Calling a match to a court, entering its result.
      resources :matches, only: :update, controller: :tournament_matches do
        patch :call, on: :member
      end
    end

    # The customer's groups. A booking is shared with the group picked in the form (groups page or booking page).
    resources :groups, only: %i[index create destroy] do
      post :join, on: :collection
      delete :leave, on: :member
      resources :shares, only: :destroy, controller: :group_shares
    end
    resources :group_shares, only: :create

    # The customer's weekly bookings with each month's bill ("Đóng tiền": ?month=YYYY-MM), and asking for a new one.
    resources :series, only: :index do
      post :pay, on: :member
    end
    resources :series_requests, only: %i[new create destroy]
    # Prepaid hours (UD-04): the packages on sale and the customer's own; buying one leads to the payment page.
    resources :packages, only: :index do
      post :buy, on: :member
    end
    # "Tell me when a court frees up" (TI-04): added from the schedule, listed on "Lượt đặt của tôi".
    resources :waitlist_entries, path: "waitlist", only: %i[create destroy]

    # The owner's area. /admin is the day board; ?date=YYYY-MM-DD picks the day.
    namespace :admin do
      root "boards#show"
      resources :bookings, only: %i[show new create], param: :code do
        member do
          patch :mark_paid
          patch :cancel
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
          # Moving the future sessions to another court or time: form -> plan (conflicts resolved) -> move.
          get :move, action: :edit_move
          post :move, action: :preview_move
          patch :move
        end
      end
      resources :series_requests, only: [] do
        patch :decline, on: :member
      end
      resources :products, except: %i[show destroy]
      resources :vouchers, except: %i[show destroy]
      resources :packages, except: %i[show destroy]
      resources :announcements, except: :show do
        delete :destroy_many, on: :collection
      end
      resources :reviews, only: :index
      resources :play_sessions, only: %i[index new create show] do
        member do
          patch :cancel
          patch :check_in
          patch :mark_refunded
        end
      end
      get "reports", to: "reports#show", as: :reports
      get "reports/customers", to: "customer_reports#show", as: :customer_reports
      # The cash drawer per shift ("chốt ca"): open, close by counting; the owner sees the history.
      resources :cash_shifts, path: "shifts", only: %i[index show create] do
        patch :close, on: :member
      end
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
      # The customer gives up before transferring: what is held is released at once.
      patch :cancel, on: :member
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
      resource :session, only: %i[create destroy] do
        post :google
      end
      resource :registration, only: :create do
        post :google
      end
      # Push notifications: the phone's FCM token (POST to add or refresh, DELETE to stop).
      resource :device_tokens, only: %i[create destroy]
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
      resources :payments, only: :show, param: :token do
        patch :cancel, on: :member
      end
      resource :quote, only: :create
      resources :packages, only: :index do
        post :buy, on: :member
      end
      resources :announcements, only: :index
      resources :play_sessions, only: :index do
        post :tickets, on: :member, action: :buy
      end
      resources :tickets, only: :destroy, controller: :play_session_tickets
      resources :tournaments, param: :token, only: %i[index show create update destroy] do
        member do
          post :draw
          delete :draw, action: :undo_draw
          patch :bookings, action: :link_bookings
          post :organize, action: :join
          patch :organizer_link, action: :reset_organizer_link
          delete :organizers, action: :remove_organizer
        end
        resources :entries, only: %i[create update destroy], controller: :tournament_entries
        resources :matches, only: :update, controller: :tournament_matches do
          patch :call, on: :member
        end
      end
      resources :groups, only: %i[index create destroy] do
        post :join, on: :collection
        delete :leave, on: :member
        resources :shares, only: %i[create destroy], controller: :group_shares
      end
      resources :waitlist_entries, path: "waitlist", only: %i[index create destroy]
      resources :series_requests, only: %i[index create destroy]
      resources :series, only: :index do
        # A transfer code for a month (YYYY-MM) still to pay.
        post :pay, on: :member
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Android App Links: which app may open this server's links (no locale, no session).
  get ".well-known/assetlinks.json", to: "well_known/asset_links#show", as: :android_asset_links, format: false

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
