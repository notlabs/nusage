#!/usr/bin/env nu
use ../common.nu *
const here = path self | path dirname
export def edges [packages: list<any>, projects: list<any>, from: record] {
    $packages | where {|p| $p.Module?.Dir? != null } | each {|p|
        let module = $p.Module.Path
        let to = $projects | where id == $"go:($module)" | get -o 0
        if $to != null and $to.id != $from.id {
            {kind: edge, from: $from.id, to: $to.id, type: go-import, source: $"($from.root)/go.mod:1"}
        }
    } | compact | uniq
}
def main [root: path = ".", --discovery: path] {
    let root = $root | path expand --no-symlink
    let data = load-discovery $discovery
    let projects = $data.native | where id =~ '^go:'
    let records = $projects | par-each {|project|
        cd ($root | path join $project.root)
        let packages = checked go list -mod=readonly -deps -test -f (open --raw ($here | path join package.gotmpl)) ./... | lines | each { from json --strict }
        (edges $packages $projects $project) ++ ($packages | where {|p| $p.Dir? != null and (within $p.Dir $root) } | each {|p|
            ($p.GoFiles? | default []) ++ ($p.TestGoFiles? | default []) ++ ($p.XTestGoFiles? | default []) | each {|file| input ($p.Dir | path join $file) }
        } | flatten) ++ [(input ($project.root | path join go.mod)) (input ($project.root | path join go.sum))]
    } | flatten
    $records ++ [
        (input 'go.work')
        (input ($here | path join package.gotmpl))
        (input ($here | path join provider.nu))
        (input ($here | path join ../common.nu | path expand --no-symlink))
    ]
    | emit
    | print
}
