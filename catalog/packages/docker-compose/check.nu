#!/usr/bin/env nu
# The baseline's offline smoke check; no daemon, containers or project required.
use std/assert
use docker-compose *

let version = docker-compose version
assert equal ($version | describe) 'record<version: string>'
assert ($version.version | str starts-with 'v')
