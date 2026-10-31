#!/usr/bin/env nu
# Check jj's raw JSON against the reviewed output schemas. The catalog's `check` runs this;
# `--bin` names a candidate jj binary, the one on PATH otherwise. A plain Nushell script: to
# the nus interpreter, the package's `mod.nu` beside it would read as the root of a tree.
use ../../schemas/lib.nu [load-suite check-examples run-suite finish]

const here = path self | path dirname

def main [--bin: string] {
    let suite = load-suite ($here | path join schemas outputs.nuon)

    let binary = if $bin != null {
        $bin | path expand
    } else {
        which jj | first | get path
    }

    finish (check-examples $suite (open ($here | path join schemas examples.nuon)))

    # The repository the cases run in, built in a home of its own: jj keeps each repository's
    # configuration under the user's configuration directory, and reads the user's files, so
    # neither is the user's. The user's `JJ_*` settings are hidden for the same reason.
    let scratch = mktemp -d

    let result = try {
        let home = $scratch | path join home
        mkdir $home
        let config = $scratch | path join config.toml
        "[user]\nname = \"nusage\"\nemail = \"nusage@example.com\"\n" | save $config
        let inherited = $env | columns | where {|name| $name | str starts-with "JJ_" }
        hide-env --ignore-errors ...$inherited
        with-env {HOME: $home, XDG_CONFIG_HOME: ($home | path join .config), JJ_CONFIG: $config} {
            let setup = {|dir: path, args: list<string>|
                let done = do {
                    cd $dir
                    ^$binary ...$args | complete
                }
                if $done.exit_code != 0 {
                    error make --unspanned {msg: $"Fixture setup failed: jj ($args | str join ' '): ($done.stderr)"}
                }
            }
            let origin = $scratch | path join origin
            let repo = $scratch | path join repo
            do $setup $scratch [git init --colocate origin]
            "a\n" | save ($origin | path join a.txt)
            do $setup $origin [commit --message first]
            do $setup $origin [bookmark create --revision @- main]
            do $setup $scratch [git clone --colocate origin repo]
            "b\n" | save ($repo | path join b.txt)
            do $setup $repo [describe --message second]
            do $setup $repo [bookmark create --revision @ feature]
            do $setup $repo [tag set --revision @- v1]
            do $setup $repo [workspace add ../second]
            do $setup $repo [bookmark delete main]
            run-suite $suite $binary $repo
        }
    } catch {|err|
        rm -r $scratch
        error make --unspanned {msg: $err.msg}
    }
    rm -r $scratch
    finish $result
}
