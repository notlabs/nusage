# The imports, test imports included, between the workspace's Go modules, as typed edges in
# `.cache/graph/go.json` for the project graph.
use common.nu *

# Go writes compact JSON through its template formatter, a package to a line.
const format = '{{if .Module}}{"package":{{printf "%q" .ImportPath}},"module":{{printf "%q" .Module.Path}},"imports":[{{range $i,$v := .Imports}}{{if $i}},{{end}}{{printf "%q" $v}}{{end}}]}{{end}}'

def analyze [root: string] {
    cd $root
    let work = $root | path join go.work
    let modules = if ($work | path exists) {
        checked go work edit -json $work | from json | get -o Use | default [] | each {|use|
            let dir = $root | path join $use.DiskPath | path expand
            {
                module: (checked go mod edit -json ($dir | path join go.mod) | from json | get Module.Path)
                root: ($dir | workspace-path $root)
            }
        }
    } else { [] }
    let packages = $modules | each {|module|
        with-env {GOWORK: $work} {
            cd ($root | path join $module.root)
            checked go list -mod=readonly -deps -test -f $format ./...
        }
        | lines
        | where $it != ""
        | each { from json }
    } | flatten
    let owners = $packages | select package module | uniq
    let workspace = $modules | get module
    let edges = $packages
    | where module in $workspace
    | each {|package|
        $package.imports | each {|imported|
            $owners | where package == $imported and module in $workspace and module != $package.module | each {|owner|
                {
                    from: $"go:($package.module)"
                    to: $"go:($owner.module)"
                    kind: go-import
                    source: $"($package.package) imports ($imported)"
                }
            }
        } | flatten
    }
    | flatten
    | sort-by from to source
    | uniq-by from to
    let output = $root | path join .cache graph go.json
    write-if-changed $output ({modules: $modules, edges: $edges} | to json --indent 2) | ignore
}

def main [root: path = "."] {
    try { analyze ($root | path expand) } catch {|err| $err | report-failure go-imports }
}
