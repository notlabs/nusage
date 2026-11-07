;; extends
; A script's header: its `#USAGE` lines, read as one KDL document, usage's, each line from
; after its prefix to its end, the line break included so the lines join.
((comment) @injection.content
  (#match? @injection.content "^#USAGE")
  (#offset! @injection.content 0 6 0 1)
  (#set! injection.language "kdl")
  (#set! injection.combined))

((comment) @injection.content
  (#match? @injection.content "^#\\[USAGE\\]")
  (#offset! @injection.content 0 8 0 1)
  (#set! injection.language "kdl")
  (#set! injection.combined))

((comment) @injection.content
  (#match? @injection.content "^# \\[USAGE\\]")
  (#offset! @injection.content 0 9 0 1)
  (#set! injection.language "kdl")
  (#set! injection.combined))
