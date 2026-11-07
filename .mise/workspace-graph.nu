# Prepare native Mise overrides from project-local metadata and Go imports.
use mise *
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
    let root = $name | parse --regex '^//(?<root>[^:]*):' | get -o root.0
    if $root == "" { "." } else { $root }
}

def within [path: string, directory: string] {
    $path == $directory or ($path | str starts-with ($directory + "/"))
}

def prepare [root: path] {
    let root = $root | path expand
    cd $root
    let output = $root | path join .mise conf.d _workspace-graph.toml

    # Let Go discover modules in source directories, keeping hidden managed artifacts out.
    if not ("go.work" | path exists) {
        checked go work init | ignore
    }
    let previous = checked go work edit -json | from json | get -o Use | default []
    if ($previous | is-not-empty) {
        (checked
            go
            work
            edit
            ...($previous | get DiskPath | each {|p| $"-dropuse=($p)" })
        ) | ignore
    }
    if ("go.mod" | path exists) {
        checked go work use . | ignore
    }
    let sources = glob "[!.]*" --no-file --no-symlink | where {|p| ($p | path type) == dir }
    if ($sources | is-not-empty) {
        checked go work use -r ...$sources | ignore
    }

    # Read only the original configuration, never our previous generated supplement.
    let ignored = [$env.MISE_IGNORED_CONFIG_PATHS? $output] | compact | str join (char esep)
    let discovered = with-env {MISE_IGNORED_CONFIG_PATHS: $ignored} {
        let policy = open mise.toml | get monorepo.config_roots
        let directories = [($root)] ++ ($policy | each {|pattern| glob $pattern } | flatten)
            | where {|p| ($p | path type) == dir }
            | each { path expand }
            | where {|p| within $p $root }
            | uniq
        # Ask Mise which files are active: this also handles local config fragments.
        let configs = $directories | par-each {|directory|
            cd $directory
            let local = mise config ls | get path
                | where {|file| (within $file $directory) and ($file | path parse | get extension) == toml }
            if ($local | is-not-empty) {
                let added = $local | each {|file|
                    open $file | get -o _.nusage.project.depends_add | default []
                } | flatten | uniq | sort
                let relative = $directory | path relative-to $root
                {root: (if $relative == "" { "." } else { $relative }), depends_add: $added}
            }
        } | sort-by root
        {
            configs: $configs
            tasks: (mise tasks ls --all --hidden | where global == false)
            native: (mise tasks graph | get projects)
        }
    }
    let roots = $discovered.configs
    | get root
    | append (
        $discovered.tasks
        | get name
        | each { task-root $in }
        | compact
    )
    | uniq
    | sort
    let custom = $roots | where {|dir| not ($discovered.native | any {|p| $p.root == $dir})} | each {|dir|
        let name = if $dir == "." { "root" } else { $dir }
        {id: $"custom:($name)", root: $dir}
    }
    let projects = $discovered.native ++ $custom
    mut edges = []
    for config in $discovered.configs {
        let id = $projects | where root == $config.root | get id.0
        for dependency in $config.depends_add {
            if not ($projects | any {|p| $p.id == $dependency}) {
                error make --unspanned {
                    msg: $"($config.root): unknown project dependency ($dependency)"
                }
            }
            $edges = $edges | append {from: $id, to: $dependency}
        }
    }

    # A config root's tasks also exercise native projects contained in it or selected by dir.
    for native in $discovered.native {
        let owners = $custom | where {|p| $p.root != "." and (within $native.root $p.root)} | sort-by {|p| $p.root | str length}
        if ($owners | is-not-empty) {
            $edges = $edges | append {from: ($owners | last | get id), to: $native.id}
        }
        for task in $discovered.tasks {
            let owner = task-root $task.name
            if $owner == null { continue }
            let absolute = $task.dir | path expand
            if not (within $absolute $root) { continue }
            let dir = $absolute | path relative-to $root
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
