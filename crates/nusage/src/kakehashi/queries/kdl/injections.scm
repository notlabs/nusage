;; extends
; In a script's header, which is the only KDL a Nushell document holds: a `run=` that runs
; a Nushell script, by its path or through `nu` or `nus`, is Nushell; any other is the
; `sh -c` usage hands it to.
((prop
  (identifier) @_key
  (value
    (string
      (string_fragment) @injection.content)))
  (#eq? @_key "run")
  (#match? @injection.content "^((nusage|nu) +[^ ]+|\\.{1,2}/[^ ]*|/[^ ]*)\\.nu( |$)")
  (#set! injection.language "nu"))

((prop
  (identifier) @_key
  (value
    (string
      (string_fragment) @injection.content)))
  (#eq? @_key "run")
  (#not-match? @injection.content "^((nusage|nu) +[^ ]+|\\.{1,2}/[^ ]*|/[^ ]*)\\.nu( |$)")
  (#set! injection.language "sh"))
