use std/assert
use std/testing *
use common.nu task-targets

@test
def "Task selectors preserve ellipses and resolve relative project paths" [] {
    let tasks = [{name: '//crates/a:test'} {name: '//crates/b:test'} {name: '//crates/a:doc'}]
    for target in ['//crates/...:test' './crates/...:test'] {
        assert equal (task-targets $tasks $target '.') [crates/a crates/b]
    }
    assert equal (task-targets $tasks '../crates/...:test' app) [crates/a crates/b]
}
