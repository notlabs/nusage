# Implementation files follow the task source; catalog entries follow the consumer's root.
# The package writes these same names relative to the helpers it carries.
export const actions = path self | path dirname | path join ../../.mise/lib/actions.nu
export const clap = path self | path dirname | path join ../clap/spec.nu
export const schema_overlay = path self | path dirname | path join ../schemas/overlay.nu
