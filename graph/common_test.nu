use std/assert
use std/testing *
use common.nu task-targets

@test
def "Task selectors preserve ellipses and resolve relative project paths" [] {
    let tasks = [{name: '//crates/a:build'} {name: '//crates/b:build'} {name: '//crates/a:test'}]
    for target in ['//crates/...:build' './crates/...:build'] {
        assert equal (task-targets $tasks $target '.') [crates/a crates/b]
    }
    assert equal (task-targets $tasks '../crates/...:build' app) [crates/a crates/b]
}
