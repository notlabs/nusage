use std::path::PathBuf;
use std::process::ExitCode;

use usage_rs::Cli;

/// Write an OpenAPI document as a usage spec, with the HTTP mapping beside it
///
/// Each operation of the document is a command of the spec: a path parameter its positional,
/// a query or header parameter its flag, a JSON response its output with the schema. The
/// method, the path, where each parameter goes on the wire and the request body go in
/// `<name>.http.kdl` beside `<name>.usage.kdl`, and each schema in `schemas/`, all in the
/// directory `--out` names. Without `--out`, the spec alone is printed. The document is read
/// as JSON; for YAML, `open doc.yaml | to json` first.
#[derive(Cli)]
#[usage(bin = "openapi-usage", version)]
struct OpenapiUsage {
    /// The OpenAPI document, as JSON
    document: PathBuf,
    /// The directory to write the spec, the mapping and the schemas into
    #[usage(long, short = 'o')]
    out: Option<PathBuf>,
    /// The spec's `name`: the document's title as a word when absent
    #[usage(long)]
    name: Option<String>,
    /// The spec's `bin`: the name when absent
    #[usage(long)]
    bin: Option<String>,
}

fn main() -> ExitCode {
    let cli = OpenapiUsage::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("openapi-usage: {message}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: OpenapiUsage) -> Result<(), String> {
    let text = std::fs::read_to_string(&cli.document)
        .map_err(|err| format!("{}: {err}", cli.document.display()))?;
    let document: serde_json::Value =
        serde_json::from_str(&text).map_err(|err| format!("{}: {err}", cli.document.display()))?;
    let options = openapi_usage::Options {
        name: cli.name,
        bin: cli.bin,
    };
    let transformed =
        openapi_usage::transform(&document, &options).map_err(|err| err.to_string())?;
    let Some(out) = cli.out else {
        print!("{}", transformed.spec);
        return Ok(());
    };
    let name = transformed
        .spec
        .lines()
        .find_map(|line| line.strip_prefix("name "))
        .map(|name| name.trim_matches('"').to_string())
        .unwrap_or_else(|| "api".to_string());
    let write = |path: PathBuf, text: String| -> Result<(), String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|err| format!("{}: {err}", parent.display()))?;
        }
        std::fs::write(&path, text).map_err(|err| format!("{}: {err}", path.display()))
    };
    write(out.join(format!("{name}.usage.kdl")), transformed.spec)?;
    write(out.join(format!("{name}.http.kdl")), transformed.http)?;
    for (file, schema) in transformed.schemas {
        let text = serde_json::to_string_pretty(&schema).map_err(|err| err.to_string())?;
        write(out.join(file), format!("{text}\n"))?;
    }
    Ok(())
}
