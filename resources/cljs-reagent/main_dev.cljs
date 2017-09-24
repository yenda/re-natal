 (ns ^:figwheel-no-load env.$PLATFORM$.main
  (:require [reagent.core :as r]
            [$PROJECT_NAME_HYPHENATED$.$PLATFORM$.core :as core]
            [figwheel.client :as figwheel :include-macros true]))

 (enable-console-print!)

(assert (exists? core/init) "Fatal Error - Your core.cljs file doesn't define an 'init' function!!! - Perhaps there was a compilation failure?")
(assert (exists? core/app-root) "Fatal Error - Your core.cljs file doesn't define an 'app-root' function!!! - Perhaps there was a compilation failure?")

(def cnt (r/atom 0))
(defn reloader [] @cnt [core/app-root])

;; Do not delete, root-el is used by the figwheel-bridge.js
(def root-el (r/as-element [reloader]))

(figwheel/watch-and-reload
 :websocket-url "ws://$DEV_HOST$:3449/figwheel-ws"
 :heads-up-display false
 :jsload-callback #(swap! cnt inc))

(core/init)
