(ns $PROJECT_NAME_HYPHENATED$.$PLATFORM$.core
  (:require-macros [natal-shell.components :refer [view text image touchable-highlight]]
                   [natal-shell.alert :refer [alert]]
                   [rum.core :refer [defc]])
  (:require [re-natal.support :as support]
            [rum.core :as rum]))

(set! js/window.React (js/require "react-native"))

(def app-registry (.-AppRegistry js/React))
(def logo-img (js/require "./images/cljs.png"))

(defonce app-state (atom {:greeting "Hello Clojure in iOS and Android!"}))

(defc AppRoot < rum/cursored-watch [state]
          (view {:style {:flexDirection "column" :margin 40 :alignItems "center"}}
                (text {:style {:fontSize 30 :fontWeight "100" :marginBottom 20 :textAlign "center"}} (:greeting @state))
                (image {:source logo-img
                        :style  {:width 80 :height 80 :marginBottom 30}})
                (touchable-highlight {:style   {:backgroundColor "#999" :padding 10 :borderRadius 5}
                                      :onPress #(alert "HELLO!")}
                                     (text {:style {:color "white" :textAlign "center" :fontWeight "bold"}} "press me"))))

(defonce root-component-factory (support/make-root-component-factory))

(defn mount-app [] (support/mount (AppRoot app-state)))

(defn init []
      (mount-app)
      (.registerComponent app-registry "$PROJECT_NAME$" (fn [] root-component-factory)))