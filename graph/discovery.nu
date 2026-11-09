use common.nu *

export def discover [root: string, tasks: list<any>] {
    cd $root
    let tasks = $tasks | where global == false
    let graph = checked mise tasks graph --json | from json --strict | get projects
    let native = $graph | where {|p| $p.provenance.provider? != null } | select id root
    let roots = ["."] ++ ($tasks | get name | each { task-root $in }) ++ ($graph | get root) | uniq | sort
    let configs = $roots | par-each --threads 8 {|dir|
        cd ($root | path join $dir)
        checked mise config ls --json | from json --strict | get path | where {|file|
            (within $file $root) and not ($file | path basename | str starts-with "_") and (
                ($file | path dirname) == ($root | path join $dir | path expand --no-symlink) or
                ($file | path dirname) == ($root | path join $dir .mise conf.d | path expand --no-symlink)
            )
        } | each {|file| {root: $dir, file: (relative $root $file), data: (open $file)} }
    } | flatten | uniq-by root file | sort-by root file
    let declared_ids = $configs | each {|c| $c.data.monorepo?.projects? | default {} | columns } | flatten | uniq
    let declared = $graph | where {|p| $p.id in $declared_ids and $p.id not-in ($native | get id) } | select id root
    let registered = $configs | where {|c| $c.data._?.nusage?.project? != null or $c.data._?.nusage?.catalog? != null } | each {|c|
        let kind = if $c.data._.nusage.catalog? != null { "catalog" } else { "nu" }
        let name = if $c.root == "." { "root" } else { $c.root | path basename }
        {id: $"($kind):($name)", root: $c.root}
    } | uniq | where {|c| not ($native ++ $declared | any {|p| $p.root == $c.root }) }
    let projects = $native ++ $declared ++ $registered
    let duplicates = $projects | group-by id | values | where {|group| ($group | length) > 1 }
    if ($duplicates | is-not-empty) { error make {msg: $"duplicate project ids: ($duplicates | to nuon)"} }
    {
        tasks: $tasks
        native: $native
        registered: $registered
        projects: $projects
        configs: $configs
    }
}
