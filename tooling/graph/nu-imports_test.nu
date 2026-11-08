use std/assert
use std/testing *

const analyzer = path self | path dirname | path join nu-imports.nu

def --wrapped checked [...args: string] {
    let result = run-external ...$args | complete
    assert equal $result.exit_code 0 ($result.stderr + $result.stdout)
    $result.stdout | str trim
}

# The analysis of a scratch tree: its references without `include`, and its carets.
def analyze [scratch: string] {
    checked nus $analyzer $scratch | ignore
    open ($scratch | path join .cache graph nu.json)
}

def save-lines [file: string, ...lines: string] {
    $lines | str join (char nl) | $in + (char nl) | save --force $file
}

@test
def "Nushell loads constants and task calls resolve to files and tasks" [] {
    let scratch = mktemp -d | path expand
    let result = try {
        do {
        cd $scratch
        {monorepo_root: true, monorepo: {config_roots: ["[!.]*" "[!.]*/[!.]*"]}} | to toml | save mise.toml
        mkdir app/lib shared tool
        save-lines shared/helper.nu 'export def helper [] { }'
        save-lines app/lib/mod.nu 'export def value [] { 1 }'
        save-lines app/paths.nu 'export const script = path self | path dirname | path join ../shared/helper.nu' 'export const runner = path self ../tool/run.nu'
        save-lines tool/run.nu 'print run'
        (save-lines app/main.nu
            'use ../shared/helper.nu *'
            'use lib [value]'
            'use paths.nu script'
            'use $script'
            'source ../shared/helper.nu'
            'overlay use ../shared/helper.nu as h'
            'use std/assert'
            'use on-lib-dirs *'
            '^mise run --force //tool:run'
            'mise run //shared:check'
            'let x = "a"'
            'mise run $"//app:($x)"'
            'mise exec -- mise run local'
            'print "mise run //not:a-call"')
        # A suite's runs name the scratch workspaces it builds; its loads still count.
        save-lines app/main_test.nu 'use ../shared/helper.nu *' 'mise run //tool:run'
        let data = analyze $scratch
        let refs = $data.refs | select file kind line target? task? dynamic? | sort-by file line
        assert equal ($data.files | sort) [app/lib/mod.nu app/main.nu app/main_test.nu app/paths.nu shared/helper.nu tool/run.nu]
        assert equal ($refs | where file == app/main.nu | reject file) [
            {kind: nu-use, line: 1, target: shared/helper.nu, task: null, dynamic: null}
            {kind: nu-use, line: 2, target: app/lib/mod.nu, task: null, dynamic: null}
            {kind: nu-use, line: 3, target: app/paths.nu, task: null, dynamic: null}
            {kind: nu-use, line: 4, target: shared/helper.nu, task: null, dynamic: null}
            {kind: nu-source, line: 5, target: shared/helper.nu, task: null, dynamic: null}
            {kind: nu-use, line: 6, target: shared/helper.nu, task: null, dynamic: null}
            {kind: task-call, line: 9, target: null, task: "//tool:run", dynamic: null}
            {kind: task-call, line: 10, target: null, task: "//shared:check", dynamic: null}
            {kind: task-call, line: 12, target: null, task: null, dynamic: 'mise run $"//app:($x)"'}
        ]
        assert equal ($refs | where file == app/paths.nu | select kind line target) [
            {kind: nu-path, line: 1, target: shared/helper.nu}
            {kind: nu-path, line: 2, target: tool/run.nu}
        ]
        assert equal ($refs | where file == app/main_test.nu | select kind target) [{kind: nu-use, target: shared/helper.nu}]

        # A computed load is dynamic too.
        save-lines app/main.nu 'use ("a" | path join b)'
        assert equal (analyze $scratch | get refs | where file == app/main.nu | get dynamic) ['use (']
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}

@test
def "task definitions name tasks run inline Nushell and keep their carets" [] {
    let scratch = mktemp -d | path expand
    let result = try {
        do {
        cd $scratch
        mkdir app shared tool other/deep
        {monorepo_root: true, monorepo: {config_roots: ["[!.]*"]}} | to toml | save mise.toml
        save-lines shared/helper.nu 'export def helper [] { }'
        {
            tasks: {
                all: {run: [{tasks: ["./...:check"]} {task: "//tool:run"} "echo done"]}
                inline: {shell: "nu -c", run: 'use "{{ config_root }}/../shared/helper.nu" *'}
                shell: {run: 'mise run //tool:run'}
                up: {depends: ["^check" ":local" ["^build" "arg"] {task: "^docs"}]}
            }
        } | to toml | save app/mise.toml
        save-lines tool/shared.tasks.toml '[check]' 'depends = ["^check"]' 'run = "true"'
        save-lines tool/header.nu '#!/usr/bin/env nus' '#MISE depends=["^build", ":x"]' 'print x'
        # Config files below the policy's depth are no config roots; their tasks do not count.
        {tasks: {deep: {run: [{task: "//nowhere:x"}]}}} | to toml | save other/deep/mise.toml
        let data = analyze $scratch
        let refs = $data.refs | where file !~ '\.nu$'
        assert equal ($refs | select file kind task? target? include | sort-by kind task) [
            {file: app/mise.toml, kind: nu-use, task: null, target: shared/helper.nu, include: false}
            {file: app/mise.toml, kind: task-call, task: "./...:check", target: null, include: false}
            {file: app/mise.toml, kind: task-call, task: "//tool:run", target: null, include: false}
            {file: app/mise.toml, kind: task-call, task: "//tool:run", target: null, include: false}
        ]
        let line = $refs | where target? == shared/helper.nu | get 0.line
        assert (open --raw app/mise.toml | lines | get ($line - 1) | str contains 'use "{{ config_root }}/../shared/helper.nu"')
        assert equal ($data.carets | select file task depends | sort-by file depends) [
            {file: app/mise.toml, task: up, depends: "^build"}
            {file: app/mise.toml, task: up, depends: "^check"}
            {file: app/mise.toml, task: up, depends: "^docs"}
            {file: tool/header.nu, task: null, depends: "^build"}
            {file: tool/shared.tasks.toml, task: check, depends: "^check"}
        ]
        }
        null
    } catch {|err| $err}
    rm -rf $scratch
    if $result != null { error make $result }
}
