(ns env.config)

(def figwheel-urls {
                    {{#each platforms}}
                    :{{@key}} "ws://{{this.host}}:3449/figwheel-ws"
                    {{/each}}
                    })