#!/usr/bin/env nus
#USAGE arg "[root]" default="."
# The project graph mise reads, as native overrides in `.mise/conf.d/_project-graph.toml`: a
# project for each config root that declares one, named for its kind, and typed edges from
# declared dependencies, catalog specs, task directories and the Go and Nushell analyzers.
# A config root whose Nushell test suites load other files gets the `nu-test` input group
# of them, in its own `.mise/conf.d/_nu-inputs.toml`.
use common.nu *

const graph_file = ".mise/conf.d/_project-graph.toml"
const inputs_file = ".mise/conf.d/_nu-inputs.toml"
const inputs_state = ".cache/graph/inputs.json"
const project_keys = [depends_add kind name dynamic]
const native_kinds = [cargo go gradle node uv]

# Data projects: what other projects read, depending on nothing themselves.
const data_kinds = [fixtures schemas]

# The generator each kind of catalog spec source names, besides a task `mise run` runs.
const spec_generators = {clap: "gen:clap", openapi: "cargo:openapi-usage"}

def task-root [name: string]: nothing -> any {
    let root = $name | parse --regex '^//(?<root>[^:]*):' | get -o root.0
    if $root == null { null } else if $root == "" { "." } else { $root }
}

def depth [root: string]: nothing -> int {
    if $root == "." {
        0
    } else {
        $root | path split | length
    }
}

# The entry among those with a `root` whose root is deepest of the ones holding the path.
def deepest [path: string]: list<any> -> any {
    $in | where {|p| within $path $p.root } | sort-by {|p| depth $p.root } | last
}

# The file, and the line outside comments the text first appears on, for an edge's source.
def located [root: string, file: string, text: string]: nothing -> string {
    let found = open --raw ($root | path join $file) | lines | enumerate | where {|l|
        not ($l.item | str trim | str starts-with "#") and ($l.item | str contains $text)
    } | get -o 0.index
    if $found == null { $file } else { $"($file):($found + 1)" }
}

# A workspace path from a config root: below it, or through its parents.
def from-root [root: string]: string -> string {
    if $root == "." {
        $in
    } else if (within $in $root) {
        $in | str substring (($root | str length) + 1)..
    } else {
        ($root | path split | each { ".." }) ++ [$in] | path join
    }
}

def fail [lines: list<string>] {
    error make --unspanned {
        msg: ($lines | str join (char nl))
    }
}

def prepare [root: string] {
    cd $root
    let nushell = open ($root | path join .cache graph nu.json)
    let go = open ($root | path join .cache graph go.json)
    let graph = $root | path join $graph_file
    # The variable replaces `.miserc.toml`'s list wherever it is set, so it starts from that list.
    let excluded = if ($env.MISE_IGNORED_CONFIG_PATHS? | default "") != "" {
        [$env.MISE_IGNORED_CONFIG_PATHS]
    } else if ($root | path join .miserc.toml | path exists) {
        open ($root | path join .miserc.toml) | get -o ignored_config_paths | default [] | each {|p| $root | path join $p }
    } else { [] }
    let ignored = $excluded ++ [$graph] | str join (char esep)
    # Read only the original configuration, never the previous graph.
    with-env {MISE_IGNORED_CONFIG_PATHS: $ignored} {
        let policy = open mise.toml | get monorepo.config_roots
        let directories = [$root] ++ ($policy | each {|pattern| glob $pattern } | flatten)
        | where {|p| ($p | path type) == dir }
        | each { path expand }
        | where {|p| not ($p | workspace-path $root | str starts-with ..) }
        | uniq
        # Ask mise which files are active: this also takes in local config fragments.
        let configs = $directories | par-each {|directory|
            cd $directory
            let files = mise config ls | get path | where {|file|
                let relative = $file | workspace-path $directory
                not ($relative | str starts-with ..) and ($file | path parse | get extension) == toml and not ($relative | str starts-with .mise/conf.d/_)
            }
            if ($files | is-not-empty) {
                let tables = $files | each {|file| {file: ($file | workspace-path $root), data: (open $file)} }
                let projects = $tables | where {|t| ($t.data | get -o _.nusage.project) != null }
                for t in $projects {
                    let unknown = $t.data._.nusage.project | columns | where $it not-in $project_keys
                    if ($unknown | is-not-empty) {
                        fail [$"($t.file): [_.nusage.project] has no key ($unknown | str join ', '); it takes ($project_keys | str join ', ')"]
                    }
                }
                let catalog = $tables | where {|t| ($t.data | get -o _.nusage.catalog) != null } | get -o 0
                {
                    root: ($directory | workspace-path $root)
                    project: ($projects | is-not-empty)
                    kind: ($projects | get -o data._.nusage.project.kind | flatten | compact | get -o 0)
                    name: ($projects | get -o data._.nusage.project.name | flatten | compact | get -o 0)
                    depends_add: ($projects | each {|t|
                        $t.data._.nusage.project | get -o depends_add | default [] | each {|d| {to: $d, file: $t.file} }
                    } | flatten)
                    dynamic: ($projects | each {|t| $t.data._.nusage.project | get -o dynamic | default [] } | flatten)
                    catalog: (if $catalog != null { {file: $catalog.file, table: $catalog.data._.nusage.catalog} })
                    groups: ($tables | any {|t| ($t.data | get -o task_config.input_groups | default {} | is-not-empty) })
                }
            }
        } | compact | sort-by root
        let native = mise tasks graph | get projects

        # Projects: native ones, and a project for each config root that declares one.
        let named = $configs | where {|c| $c.root == "." or $c.project or $c.catalog != null }
        let issues = $named | where {|c| ($native | any {|n| $n.root == $c.root }) and ($c.kind != null or $c.name != null) } | each {|c|
            $"($c.root): a native project is there already; its [_.nusage.project] cannot set kind or name"
        }
        if ($issues | is-not-empty) { fail $issues }
        let custom = $named | where {|c| not ($native | any {|n| $n.root == $c.root }) } | each {|c|
            let kind = if $c.catalog != null { "catalog" } else { $c.kind | default nu }
            let name = $c.name | default (if $c.root == "." { "root" } else { $c.root | path basename })
            if ($kind | str contains ":") or $kind == "" or $name == "" or $kind in $native_kinds {
                fail [$"($c.root): ($kind):($name) is no project ID this graph can declare; a kind is a word that no native provider uses"]
            }
            {id: $"($kind):($name)", root: $c.root, kind: $kind}
        }
        let duplicates = $custom | group-by id | items {|id, group| {id: $id, roots: ($group | get root)} } | where ($it.roots | length) > 1
        if ($duplicates | is-not-empty) {
            fail ($duplicates | each {|d| $"($d.id) is declared by ($d.roots | str join ' and ')" })
        }
        let projects = ($native | each {|n| {id: $n.id, root: $n.root, kind: ($n.id | split row ":" | first)} }) ++ $custom
        let at = {|dir| $projects | where root == $dir | get -o 0 }
        let owner = {|path| $projects | deepest $path }
        let config_roots = $configs | get root

        # Input groups go first: tasks that name them do not load without them.
        let closure = {|start|
            mut seen = $start | uniq
            mut frontier = $seen
            while ($frontier | is-not-empty) {
                let reached = $nushell.refs
                | where {|r| $r.file in $frontier and ($r.target? | default null) != null and $r.kind in [nu-use nu-source nu-path] }
                | get target
                | uniq
                | where $it not-in $seen
                $seen = $seen ++ $reached
                $frontier = $reached
            }
            $seen | sort
        }
        let suites = $nushell.files | where ($it | str ends-with _test.nu) | each {|file|
            {file: $file, root: ($config_roots | each {|r| {root: $r} } | deepest $file | get root)}
        }
        let fragments = $suites | get root | uniq | sort | each {|group_root|
            if ($configs | where root == $group_root | get 0.groups) {
                fail [$"($group_root): its config defines [task_config.input_groups]; mise reads one file's input groups per config root, so the generated nu-test group would be dropped. Move the groups into the generated ones or out of this root"]
            }
            let files = do $closure ($suites | where root == $group_root | get file)
            let file = $root | path join $group_root $inputs_file | path expand --no-symlink
            let content = {task_config: {input_groups: {nu-test: ($files | each { from-root $group_root })}}} | to toml
            {file: $file, content: ("# Written by the project-graph provider from the Nushell analyzer; edits are replaced.\n" + $content)}
        }
        let previous = if ($root | path join $inputs_state | path exists) { open ($root | path join $inputs_state) } else { [] }
        for file in ($previous | where {|p| $p not-in ($fragments | get file) and ($p | path exists) }) {
            rm $file
        }
        for fragment in $fragments {
            write-if-changed $fragment.file $fragment.content | ignore
        }
        write-if-changed ($root | path join $inputs_state) ($fragments | get file | to json) | ignore

        let tasks = mise tasks ls --all --hidden | where global == false | each {|t|
            {
                name: $t.name
                root: (task-root $t.name)
                dir: ($t.dir | path expand --no-symlink | workspace-path $root)
                source: ($t.source | path expand --no-symlink | workspace-path $root)
            }
        }
        let task_roots = $tasks | get root | compact | uniq
        # The roots whose tasks come from the file: its own config root, or the roots that
        # include it.
        let defining = {|file|
            let including = $tasks | where source == $file | get root | compact | uniq
            if ($including | is-not-empty) { $including } else {
                [($config_roots | each {|r| {root: $r} } | deepest $file | get root)]
            }
        }
        # The config roots a task reference from a root names.
        let resolve = {|target, base|
            let spec = if ($target | str starts-with "//") {
                $target | str substring 2..
            } else if ($target | str starts-with "./") or ($target | str starts-with "../") {
                let parts = $target | split row ":"
                let dir = $root | path join $base ($parts | drop 1 | str join ":") | path expand --no-symlink | workspace-path $root
                let dir = if ($parts | drop 1 | str join ":" | str ends-with "...") and not ($dir | str ends-with "...") { $"($dir)/..." } else { $dir }
                $"(if $dir == '.' { '' } else { $dir }):($parts | last)"
            }
            if $spec == null { return [$base] }
            let parts = $spec | split row ":"
            let dir = $parts | first
            let task = $parts | skip 1 | str join ":"
            if ($dir | str ends-with "...") {
                let prefix = $dir | str replace --regex '/?\.\.\.$' '' | if $in == "" { "." } else { $in }
                $tasks | where {|t| $t.root != null and (within $t.root $prefix) and ($t.name | str ends-with $":($task)") } | get root | uniq
            } else {
                let dir = if $dir == "" { "." } else { $dir }
                if $dir not-in $task_roots and $dir not-in $config_roots {
                    null
                } else { [$dir] }
            }
        }

        mut edges = []
        mut problems = []
        # Declared: what a project's config says it reads.
        for config in ($configs | where {|c| $c.depends_add | is-not-empty }) {
            let from = do $at $config.root
            for dependency in $config.depends_add {
                let target = $projects | where id == $dependency.to | get -o 0
                if $target == null {
                    $problems = $problems | append $"($dependency.file): unknown project dependency ($dependency.to)"
                    continue
                }
                $edges = $edges | append {
                    from: $from.id
                    to: $target.id
                    kind: (if $target.kind in $data_kinds { "fixtures" } else { "declared" })
                    source: (located $root $dependency.file $'"($dependency.to)"')
                }
            }
        }
        # Spec generators: what a catalog entry's spec comes from.
        for config in ($configs | where catalog != null) {
            let from = do $at $config.root
            let spec = $config.catalog.table | get -o spec | default {}
            let run = $spec | get -o run | default "" | parse --regex 'mise run\s+(?<target>//\S+)' | get -o target.0
            let generators = $spec | columns | where $it in $spec_generators | each {|kind| $spec_generators | get $kind }
            let generators = $generators ++ (
                if $run != null {
                    do $resolve $run $config.root | default [] | each {|r| (do $at $r | default (do $owner $r)).id }
                } else { [] }
            )
            for generator in $generators {
                if not ($projects | any {|p| $p.id == $generator }) {
                    $problems = $problems | append $"($config.catalog.file): spec names generator ($generator), which is no project"
                    continue
                }
                $edges = $edges | append {from: $from.id, to: $generator, kind: spec-generator, source: (located $root $config.catalog.file "spec")}
            }
        }
        # Nushell: loads, path constants and task calls across project roots.
        let acknowledged = $configs | each {|c| $c.dynamic | each {|d| $root | path join $c.root $d | path expand --no-symlink | workspace-path $root } } | flatten
        for ref in $nushell.refs {
            let source = if $ref.line == null { $ref.file } else { $"($ref.file):($ref.line)" }
            let froms = if ($ref.include? | default false) {
                do $defining $ref.file | each {|r| do $at $r } | compact
            } else { [(do $owner $ref.file)] }
            if ($ref.dynamic? | default null) != null {
                let file_owner = do $owner $ref.file
                if $file_owner.kind not-in $data_kinds and $ref.file not-in $acknowledged {
                    let listed = if $file_owner.root == "." { $ref.file } else { $ref.file | str replace $"($file_owner.root)/" "" }
                    $problems = $problems | append $"($source): ($ref.dynamic) names no literal target; make it literal, or list ($listed) in [_.nusage.project].dynamic of ($file_owner.id) and declare what it reaches in depends_add"
                }
                continue
            }
            mut tos = []
            if ($ref.target? | default null) != null {
                $tos = [(do $owner $ref.target)]
            } else {
                for base in (do $defining $ref.file) {
                    let roots = do $resolve $ref.task $base
                    if $roots == null {
                        $problems = $problems | append $"($source): ($ref.task) names no config root"
                    } else {
                        $tos = $tos ++ ($roots | each {|r| do $at $r | default (do $owner $r) })
                    }
                }
            }
            for from in $froms {
                for to in $tos {
                    if $from.id != $to.id {
                        $edges = $edges | append {from: $from.id, to: $to.id, kind: $ref.kind, source: $source}
                    }
                }
            }
        }
        # Task directories: a project's task that runs inside another project.
        for task in ($tasks | where root != null) {
            let from = do $at $task.root
            if $from == null or ($task.dir | str starts-with ..) { continue }
            let to = do $owner $task.dir
            if $to.id != $from.id {
                let short = $task.name | str replace --regex '^//[^:]*:' ''
                $edges = $edges | append {from: $from.id, to: $to.id, kind: task-dir, source: (located $root $task.source $"[tasks.($short)]")}
            }
        }
        # Go: imports between the workspace's modules.
        let native_ids = $native | get id
        $edges = $edges ++ ($go.edges | where from in $native_ids and to in $native_ids)

        # `^task` dependencies only resolve in a task whose root is a project.
        for caret in $nushell.carets {
            let source = if $caret.line == null { $caret.file } else { $"($caret.file):($caret.line)" }
            for task_root in (do $defining $caret.file) {
                if (do $at $task_root) == null {
                    $problems = $problems | append $"($source): ($caret.depends) in ($task_root), which is no project, where mise drops it; declare [_.nusage.project] there or depend on the tasks by name"
                }
            }
        }
        # Edge kinds the project kinds allow.
        let kind_of = {|id| $projects | where id == $id | get 0.kind }
        for edge in $edges {
            let from_kind = do $kind_of $edge.from
            let to_kind = do $kind_of $edge.to
            if $from_kind in $data_kinds {
                $problems = $problems | append $"($edge.source): ($edge.from) depends on ($edge.to), but a ($from_kind) project depends on nothing"
            } else if $from_kind == gen and $to_kind == catalog {
                $problems = $problems | append $"($edge.source): generator ($edge.from) depends on catalog entry ($edge.to); entries depend on their generators, not the reverse"
            }
        }
        if ($problems | is-not-empty) { fail ($problems | uniq) }

        let edges = $edges | uniq | sort-by from to kind source
        # A cycle stops mise from loading any task; name the edges that close it.
        let adjacency = $projects | each {|p|
            let declared = $native | where id == $p.id | get -o 0.dependencies | default []
            {id: $p.id, to: ($declared ++ ($edges | where from == $p.id | get to) | uniq)}
        }
        mut state = {}
        for start in ($adjacency | get id) {
            if ($state | get -o $start) != null { continue }
            mut stack = [{id: $start, next: 0}]
            mut path = [$start]
            $state = $state | upsert $start active
            while ($stack | is-not-empty) {
                let top = $stack | last
                let targets = $adjacency | where id == $top.id | get 0.to
                if $top.next >= ($targets | length) {
                    $state = $state | upsert $top.id done
                    $stack = $stack | drop 1
                    $path = $path | drop 1
                    continue
                }
                $stack = ($stack | drop 1) ++ [($top | update next ($top.next + 1))]
                let target = $targets | get $top.next
                match ($state | get -o $target) {
                    active => {
                        let cycle = ($path | skip until {|id| $id == $target }) ++ [$target]
                        let links = $cycle | window 2 | each {|pair|
                            let typed = $edges | where from == $pair.0 and to == $pair.1 | each {|e| $"($e.kind) at ($e.source)" }
                            $"($pair.0) -> ($pair.1)" + (if ($typed | is-empty) { " (native)" } else { $" \(($typed | str join ', '))" })
                        }
                        fail [$"project dependency cycle: ($links | str join ', ')"]
                    }
                    done => { }
                    _ => {
                        $state = $state | upsert $target active
                        $stack = $stack | append {id: $target, next: 0}
                        $path = $path | append $target
                    }
                }
            }
        }

        # Overrides: custom projects with their root, and every project with added edges.
        # `depends_add` keeps only targets; each project's metadata keeps the typed edges.
        let overrides = $projects | sort-by id | reduce --fold {} {|p, acc|
            let own = $edges | where from == $p.id
            let typed = $own | select to kind source | to json --raw
            if ($custom | any {|c| $c.id == $p.id }) {
                $acc | insert $p.id {
                    root: $p.root
                    depends_add: ($own | get to | uniq | sort)
                    metadata: {kind: $p.kind, edges: $typed}
                }
            } else if ($own | is-not-empty) {
                let metadata = $native | where id == $p.id | get 0.metadata | default {}
                $acc | insert $p.id {depends_add: ($own | get to | uniq | sort), metadata: ($metadata | merge {edges: $typed})}
            } else { $acc }
        }
        let monorepo = {projects: $overrides}
        let fingerprint = [({monorepo: $monorepo} | to toml)] ++ ($fragments | get content) | str join "\n" | hash sha256
        let content = "# Written by the project-graph provider (tooling/graph/project-graph.nu); edits are replaced.\n" + ({vars: {project_graph: $fingerprint}, monorepo: $monorepo} | to toml)
        write-if-changed $graph $content | ignore
    }
}

def build-graph [root: path] {
    try {
        prepare ($root | path expand)
    } catch {|err|
        $err | report-failure project-graph
    }
}

build-graph $usage.args.root
