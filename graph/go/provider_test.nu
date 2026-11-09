use std/assert
use std/testing *
use ../common.nu load-discovery
use provider.nu edges
const here = path self | path dirname
@test
def "Go imports join only discovered workspace modules and deduplicate" [] {
    let projects = load-discovery ($here | path join fixtures discovery.json) | get native
    assert equal (edges (open ($here | path join fixtures packages.json)) $projects $projects.0) [{kind: edge, from: 'go:example.test/a', to: 'go:example.test/b', type: go-import, source: 'a/go.mod:1'}]
}
