#!/usr/bin/env nusage
#USAGE about "Drives mise through the generated module: each call decodes to the data it declares"
use std/assert
use generated/mise.nu *

let version = mise version
assert ($version.version =~ '^\d{4}\.\d+\.\d+') ($version | to nuon)

let tasks = mise tasks ls
assert ($tasks | any {|task| $task.name ends-with "check" }) ($tasks | get name | to nuon)
assert ((mise tasks ls --hidden | length) >= ($tasks | length))

let task = mise tasks info check
assert equal ($task.file | path basename) check.nu ($task | to nuon)

let configs = mise config ls
assert (($configs | get path) | any {|path| ($path | path basename) == mise.toml }) ($configs | to nuon)

print $"mise: ($tasks | length) tasks through the module"
