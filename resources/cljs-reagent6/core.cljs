(ns $PROJECT_NAME_HYPHENATED$.$PLATFORM$.core
  (:require [reagent.core :as r :refer [atom]]
            [re-frame.core :refer [subscribe dispatch dispatch-sync]]
            [$PROJECT_NAME_HYPHENATED$.events]
            [$PROJECT_NAME_HYPHENATED$.subs]
            [react-native :as rn]))

(def app-registry rn/AppRegistry)
(def text (r/adapt-react-class rn/Text))
(def view (r/adapt-react-class rn/View))
(def image (r/adapt-react-class rn/Image))
(def touchable-highlight (r/adapt-react-class rn/TouchableHighlight))

(def logo-img (js/require "./images/cljs.png"))

(defn alert [title]
      (.alert rn/Alert title))

(defn app-root []
  (let [greeting (subscribe [:get-greeting])]
    (fn []
      [view {:style {:flex-direction "column" :margin 40 :align-items "center"}}
       [text {:style {:font-size 30 :font-weight "100" :margin-bottom 20 :text-align "center"}} @greeting]
       [image {:source logo-img
               :style  {:width 80 :height 80 :margin-bottom 30}}]
       [touchable-highlight {:style {:background-color "#999" :padding 10 :border-radius 5}
                             :on-press #(alert "HELLO!")}
        [text {:style {:color "white" :text-align "center" :font-weight "bold"}} "press me"]]])))

(defn init []
      (dispatch-sync [:initialize-db])
      (.registerComponent app-registry "$PROJECT_NAME$" #(r/reactify-component app-root)))
