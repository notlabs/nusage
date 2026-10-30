//! The petstore, as OpenAPI 3.0 has it, through the transformer: the spec usage parses, the
//! mapping beside it, and the schemas in the dialect.

use std::path::Path;

use openapi_usage::{Options, Transformed, transform};

fn petstore() -> serde_json::Value {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/petstore.json");
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

/// The spec and its schemas written where usage can read them together.
fn written(transformed: &Transformed, name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("openapi-usage-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("schemas")).unwrap();
    std::fs::write(dir.join("api.usage.kdl"), &transformed.spec).unwrap();
    for (file, schema) in &transformed.schemas {
        std::fs::write(
            dir.join(file),
            serde_json::to_string_pretty(schema).unwrap(),
        )
        .unwrap();
    }
    dir
}

#[test]
fn the_petstore_is_a_spec_usage_parses() {
    let transformed = transform(&petstore(), &Options::default()).unwrap();
    insta::assert_snapshot!("spec", transformed.spec);
    insta::assert_snapshot!("http", transformed.http);
    let files: Vec<&String> = transformed.schemas.keys().collect();
    assert_eq!(
        files,
        [
            "schemas/create-pets.body.schema.json",
            "schemas/list-pets.schema.json",
            "schemas/show-pet-by-id.schema.json",
        ]
    );
    for (file, schema) in &transformed.schemas {
        insta::assert_json_snapshot!(file.as_str(), schema);
    }
    // usage reads the spec, with every command, and finds the schema files beside it.
    let dir = written(&transformed, "parses");
    let spec = usage::Spec::parse_file(&dir.join("api.usage.kdl")).unwrap();
    let mut names: Vec<&String> = spec.cmd.subcommands.keys().collect();
    names.sort();
    assert_eq!(
        names,
        [
            "create-pets",
            "delete-pets-pet-id",
            "list-pets",
            "show-pet-by-id"
        ]
    );
    let list = &spec.cmd.subcommands["list-pets"];
    assert_eq!(list.help.as_deref(), Some("List all pets"));
    let flags: Vec<&str> = list.flags.iter().map(|flag| flag.name.as_str()).collect();
    assert_eq!(flags, ["limit", "status", "tags", "x-request-id"]);
    assert_eq!(
        spec.cmd.subcommands["delete-pets-pet-id"]
            .deprecated
            .as_deref(),
        Some("deprecated")
    );
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn the_schemas_are_in_the_dialect() {
    let transformed = transform(&petstore(), &Options::default()).unwrap();
    for (file, schema) in &transformed.schemas {
        nushell_schema::validate::conforms(schema).unwrap_or_else(|err| panic!("{file}: {err}"));
        nushell_schema::shape_of(schema).unwrap_or_else(|err| panic!("{file}: {err}"));
    }
    // A pet is a new pet with an id, as the document's `allOf` says.
    let pets =
        nushell_schema::shape_of(&transformed.schemas["schemas/list-pets.schema.json"]).unwrap();
    assert_eq!(
        pets.ty.as_str(),
        "table<name: string, tag: oneof<string, nothing>, owner: oneof<record<name: string, pets: oneof<int, nothing>>, nothing>, born: oneof<datetime, nothing>, id: int>"
    );
}

#[test]
fn the_name_is_the_titles_word_unless_said() {
    let named = transform(
        &petstore(),
        &Options {
            name: Some("pets".into()),
            bin: Some("petctl".into()),
        },
    )
    .unwrap();
    assert!(
        named.spec.starts_with("name \"pets\"\nbin \"petctl\"\n"),
        "{}",
        named.spec
    );
}

#[test]
fn what_is_not_read_says_so() {
    let mut doc = petstore();
    doc["openapi"] = "2.0".into();
    assert!(matches!(
        transform(&doc, &Options::default()),
        Err(openapi_usage::Error::Version(_))
    ));
    let mut doc = petstore();
    doc["paths"]["/pets"]["get"]["responses"]["200"]["content"]["application/json"]["schema"] =
        serde_json::json!({"$ref": "https://example.com/pet.json"});
    assert!(matches!(
        transform(&doc, &Options::default()),
        Err(openapi_usage::Error::Reference { .. })
    ));
}
