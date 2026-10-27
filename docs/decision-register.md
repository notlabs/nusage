# Decisions

Settled for the first implementation stage. Earlier drafts of this file listed alternatives;
they are gone because the choices below are made.

- **Attributes are per usage property.** `@requires key [identity]`, `@env key APP_KEY`, and
  so on, one alias per property in a shared `attrs.nu`, each attribute's value its argument
  list. Only properties with no native Nushell form become attributes: usage `deprecated`,
  `example`, and completion go to `@deprecated`, `@example`, and generated completers.
- **Scripts are header plus body.** No `def main`, no signature, nothing generated inside a
  user's file. The script reads `$usage`, declared by the shim before `$in | run <script>`.
- **The spec is the header of each script.** A tree is assembled from per-file `#USAGE`
  fragments along the directory layout, `mod.nu` holding the parent's `name`, `bin`, `about`
  and global flags. usage's own one-spec form keeps parsing because usage-lib does, but it is
  not authored here.
- **The generator writes a module to the path it is given.** Where that path is, and whether
  it is committed, is the caller's business, not a policy.
- **No enforcement work in this stage.** The shim carries the signature and the attributes.
  Anything a Nushell signature cannot check is not checked in-session until the parse-time
  stage, which is engine work and explicitly deferred. The interpreter entrypoint, when
  built, gets usage's own parser and therefore its checks.
- **Nushell 0.116.** The pinned version; nothing in the shim path needs 0.117. `type`
  aliases and `@structured` wait for it.
- **Plain `run`.** No reparse policy. If editing scripts during a session turns out to hurt,
  `--full-reparse` exists.
- **Values are what the signature says.** Positionals and flag values are `string`, `<file>`
  and `<dir>` are `path`, switches `bool`, variadics `list<string>`, counts `int`. A way to
  declare other Nushell types for a usage argument is not designed; it is a later addition.

What the fixtures already pin, unchanged: the `$usage` record shape, every declared name
present, globals first, the shim body, nufmt-stable layout, `scope commands` as the signature
oracle.
