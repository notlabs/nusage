//! Every fixture under `fixtures/` generates byte for byte what its `expected/<bin>.nu` says.
//!
//! The fixtures are the design: a hand-written target module per script or tree, with the
//! cases `fixtures/verify.nu` runs against the pinned Nushell. This test keeps the generator
//! honest to them; `mise run verify-fixtures` keeps them honest to Nushell.

use std::fs;
use std::path::{Path, PathBuf};

fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures")
}

/// The source of a fixture: its single `script.nu`, or its `<bin>/` tree.
fn source_of(fixture: &Path, bin: &str) -> PathBuf {
    let single = fixture.join("script.nu");
    if single.is_file() {
        single
    } else {
        fixture.join(bin)
    }
}

#[test]
fn fixtures_generate_their_expected_modules() {
    let mut checked = 0;
    let mut failures = Vec::new();
    let mut fixtures: Vec<PathBuf> = fs::read_dir(fixtures_dir())
        .expect("fixtures directory")
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.is_dir())
        .collect();
    fixtures.sort();
    for fixture in fixtures {
        let expected_dir = fixture.join("expected");
        let module_file = fs::read_dir(&expected_dir)
            .expect("expected directory")
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .find(|path| path.extension().is_some_and(|ext| ext == "nu"))
            .expect("expected/<bin>.nu");
        let bin = module_file.file_stem().unwrap().to_str().unwrap();
        let source = source_of(&fixture, bin);
        let expected = fs::read_to_string(&module_file).unwrap();
        match nusage::generate(&source, Some(&module_file)) {
            Ok(actual) if actual == expected => checked += 1,
            Ok(actual) => failures.push(format!(
                "{}: generated module differs from {}\n--- expected\n{expected}--- actual\n{actual}",
                fixture.display(),
                module_file.display()
            )),
            Err(err) => failures.push(format!("{}: {err}", fixture.display())),
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
    assert!(
        checked >= 3,
        "expected at least three fixtures, found {checked}"
    );
}
