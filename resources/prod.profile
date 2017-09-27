                                                   {:id           "$PLATFORM$"
                                                    :source-paths ["src" "env/prod"]
                                                    :compiler     {:output-to     "index.$PLATFORM$.js"
                                                                   :main          "env.$PLATFORM$.main"
                                                                   :output-dir    "target/$PLATFORM$"
                                                                   :static-fns    true
                                                                   :optimize-constants true
                                                                   :optimizations :simple
                                                                   :target :nodejs
                                                                   :npm-deps {:react-native "0.48.4"
                                                                              :react "16.0.0-alpha.12"
                                                                              :create-react-class "15.6.0"}
                                                                   :install-deps true
                                                                   :closure-defines {"goog.DEBUG" false}}}