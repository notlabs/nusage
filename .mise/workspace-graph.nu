# Prepare Mise's supplement from discovered tasks and Go's resolved imports.
def --wrapped checked [...args: string]: any -> string {
    let input = $in
    let result = $input | run-external ...$args | complete
    if $result.exit_code != 0 {
        error make --unspanned {
            msg: ($result.stderr + $result.stdout)
        }
    }
    $result.stdout
}

def task-root [name: string] {
    $name | parse --regex '^//(?<root>[^:]*):' | get -o root.0
}

def within [path: string, directory: string] {
    $path == $directory or ($path | str starts-with ($directory + "/"))
}

def prepare [root: path] {
    let root = $root | path expand
    cd $root
    let output = $root | path join .mise conf.d _workspace-graph.toml

    # This is a real Go workspace. Go discovers membership, including removed modules.
    if not ("go.work" | path exists) {
        checked go work init | ignore
    }
    checked go work use -r . | ignore

    # Read only the original configuration, never our previous generated supplement.
    let ignored = [$env.MISE_IGNORED_CONFIG_PATHS? $output] | compact | str join (char esep)
    let discovered = with-env {MISE_IGNORED_CONFIG_PATHS: $ignored} {
        {
            tasks: (checked mise tasks ls --all --hidden --json | from json | where global == false)
            native: (checked mise tasks graph --json | from json | get projects)
            dag: (checked mise tasks deps --dot --hidden)
        }
    }
    let roots = $discovered.tasks | get name | each { task-root $in } | compact | where $it != "" | uniq | sort
    let custom = $roots | where {|dir| not ($discovered.native | any {|p| $p.root == $dir})} | each {|dir|
        {id: $"custom:($dir)", root: $dir}
    }
    let projects = $discovered.native ++ $custom
    mut edges = []

    # Mise resolves aliases, globs and argument-bearing prerequisites into this DAG.
    let nodes = $discovered.dag | lines | parse --regex '^\s*(?<index>\d+) \[ label = (?<label>".*")\]$' | each {|n|
        {index: $n.index, root: (task-root ($n.label | from json))}
    }
    for edge in ($discovered.dag | lines | parse --regex '^\s*(?<from>\d+) -> (?<to>\d+)') {
        let from = $nodes | where index == $edge.from | get root.0
        let to = $nodes | where index == $edge.to | get root.0
        if $from != null and $to != null and $from != "" and $to != "" and $from != $to {
            let a = $projects | where root == $from | get id.0
            let b = $projects | where root == $to | get id.0
            $edges = $edges | append {from: $a, to: $b}
        }
    }

    # A config root's tasks also exercise native projects contained in it or selected by dir.
    for native in $discovered.native {
        let owners = $custom | where {|p| within $native.root $p.root} | sort-by {|p| $p.root | str length}
        if ($owners | is-not-empty) {
            $edges = $edges | append {from: ($owners | last | get id), to: $native.id}
        }
        for task in $discovered.tasks {
            let owner = task-root $task.name
            if $owner == null or $owner == "" { continue }
            let dir = $task.dir | path expand | path relative-to $root
            if $owner != $native.root and (within $dir $native.root) {
                let id = $projects | where root == $owner | get id.0
                $edges = $edges | append {from: $id, to: $native.id}
            }
        }
    }

    # Go emits compact JSON through its standard template formatter; Nu reads JSONL.
    let format = '{{if .Module}}{"package":{{printf "%q" .ImportPath}},"module":{{printf "%q" .Module.Path}},"imports":[{{range $i,$v := .Imports}}{{if $i}},{{end}}{{printf "%q" $v}}{{end}}]}{{end}}'
    mut packages = []
    for project in ($discovered.native | where id =~ '^go:') {
        let listed = with-env {GOWORK: ($root | path join go.work)} {
            cd ($root | path join $project.root)
            checked go list -mod=readonly -deps -test -f $format ./...
        }
        $packages = $packages ++ (
            $listed
            | lines
            | where $it != ""
            | each { from json }
        )
    }
    for package in $packages {
        let from = $"go:($package.module)"
        if not ($discovered.native | any {|p| $p.id == $from}) { continue }
        for imported in $package.imports {
            for target in (
                $packages
                | where package == $imported
                | get module
                | uniq
            ) {
                let to = $"go:($target)"
                if $to != $from and ($discovered.native | any {|p| $p.id == $to}) {
                    $edges = $edges | append {from: $from, to: $to}
                }
            }
        }
    }

    let edges = $edges
    let overrides = $projects | sort-by id | reduce --fold {} {|p, acc|
        let added = $edges | where from == $p.id | get to | uniq | sort
        if ($custom | any {|c| $c.id == $p.id}) {
            $acc | merge {($p.id): {root: $p.root, depends_add: $added}}
        } else if ($added | is-not-empty) {
            $acc | merge {($p.id): {depends_add: $added}}
        } else { $acc }
    }
    let content = {
        monorepo: {projects: $overrides}
    } | to toml
    mkdir ($output | path dirname)
    if not ($output | path exists) or (open --raw $output) != $content {
        let temporary = $"($output).tmp"
        $content | save --force $temporary
        mv --force $temporary $output
    }
}

# Providers report only their final stderr line. Keep the actual failure on that line.
def main [root: path = "."] {
    try { prepare $root } catch {|err|
        let detail = $err.msg | lines | where $it != "" | str join " | "
        print --stderr $"workspace graph: ($detail)"
        exit 1
    }
}
