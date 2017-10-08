(ns ^:figwheel-no-load env.$PLATFORM$.main
  (:require [om.next :as om]
            [$PROJECT_NAME_HYPHENATED$.$PLATFORM$.core :as core]
            [$PROJECT_NAME_HYPHENATED$.state :as state]
            [figwheel.client :as fw]
            [env.config :as conf]))

(enable-console-print!)

(assert (exists? core/init) "Fatal Error - Your core.cljs file doesn't define an 'init' function!!! - Perhaps there was a compilation failure?")
(assert (exists? core/app-root) "Fatal Error - Your core.cljs file doesn't define an 'app-root' function!!! - Perhaps there was a compilation failure?")

(fw/start {
           :websocket-url    (:$PLATFORM$ conf/figwheel-urls)
           :heads-up-display false
           :jsload-callback  #(om/add-root! state/reconciler core/AppRoot 1)})

(core/init)

;; Do not delete, root-el is used by the figwheel-bridge.js
(def root-el (core/app-root))
