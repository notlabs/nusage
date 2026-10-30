#!/usr/bin/env nu
# Check gh's raw JSON against the reviewed output schemas. The catalog's `check` runs this;
# `--bin` names a candidate gh binary, the one on PATH otherwise. The cases read this
# repository on GitHub, so they run with a token, `GH_TOKEN` or `GITHUB_TOKEN`, and without
# one only the examples are checked, a failure in CI. A plain Nushell script: to the nusage
# interpreter, the package's `mod.nu` beside it would read as the root of a tree.
use ../../schemas/lib.nu [load-suite check-examples run-suite finish]

const here = path self | path dirname

def main [--bin: string] {
    let suite = load-suite ($here | path join schemas outputs.nuon)

    let binary = if $bin != null {
        $bin | path expand
    } else {
        which gh | first | get path
    }

    # The schemas themselves, then the documents they must accept or reject.
    finish (check-examples $suite (open ($here | path join schemas examples.nuon)))

    let token = $env.GH_TOKEN? | default $env.GITHUB_TOKEN? | default ""
    if ($token | is-empty) {
        if ($env.CI? | default "") == "true" {
            error make --unspanned {msg: "the cases read GitHub: set GH_TOKEN"}
        }
        print "gh: no GH_TOKEN or GITHUB_TOKEN, so the cases that read GitHub are not run here"
        return
    }

    let scratch = mktemp -d
    let result = try {
        # The user's own configuration stays out: hosts, aliases and the token come from the
        # environment alone, and nothing prompts.
        with-env {
            GH_CONFIG_DIR: ($scratch | path join config)
            GH_TOKEN: $token
            GH_PROMPT_DISABLED: "1"
            GH_NO_UPDATE_NOTIFIER: "1"
            NO_COLOR: "1"
        } {
            run-suite $suite $binary $scratch
        }
    } catch {|err|
        rm -r $scratch
        error make --unspanned {msg: $err.msg}
    }
    rm -r $scratch
    finish $result
}
