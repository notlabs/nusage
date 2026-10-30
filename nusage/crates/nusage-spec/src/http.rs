//! The HTTP mapping beside a spec: `<name>.http.kdl`, as `openapi-usage` writes it, saying
//! what the call of each command sends. The spec is a usage spec like any binary's, and
//! usage reads it alone; the mapping is nusage's, read here, and holds what usage's grammar
//! has no place for: the method, the path with its `{params}`, where each parameter goes on
//! the wire, the request body, and the service's base URL and authentication.
//!
//! ```kdl
//! base "https://petstore.example.com/v1"
//! auth "bearer"
//! cmd "list-pets" method="get" path="/pets" {
//!     query "limit" flag="limit"
//!     header "X-Request-Id" flag="x-request-id"
//! }
//! cmd "show-pet-by-id" method="get" path="/pets/{petId}" {
//!     path "petId" arg="pet-id"
//! }
//! cmd "create-pets" method="post" path="/pets" {
//!     body "application/json" schema="schemas/create-pets.body.schema.json" required=#true
//! }
//! ```
//!
//! A `path`, `query` or `header` node names the parameter as the wire has it, and the
//! positional (`arg=`) or flag (`flag=`) of the spec that carries it, by usage's name. A
//! `body` names the media type, the schema file beside the mapping when the body has one,
//! and whether the call must send one. An `auth` is `bearer`, `basic`, or `header` or
//! `query` with the `name=` the key goes under.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use usage::kdl::{KdlDocument, KdlNode};

use crate::{CommandPath, Diagnostic};

/// The mapping: the service, and a request per command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Http {
    /// The base URL the paths follow, when the mapping names one.
    pub base: Option<String>,
    /// What the service asks every call to carry, in the mapping's order.
    pub auths: Vec<Auth>,
    /// Each command's request, by the command's path in the spec.
    pub commands: BTreeMap<CommandPath, Request>,
}

/// What a command's call sends.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    /// The method, lower case: `get`, `post`.
    pub method: String,
    /// The path after the base, with each path parameter as `{name}`.
    pub path: String,
    /// Where each parameter goes, in the mapping's order.
    pub params: Vec<Wire>,
    pub body: Option<Body>,
}

/// A parameter on the wire, and the spec's parameter that carries it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Wire {
    pub location: Location,
    /// The name on the wire: `petId`, `X-Request-Id`.
    pub name: String,
    /// The usage name of the spec's positional or flag.
    pub param: String,
}

/// Where a parameter goes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Location {
    /// Into the path, in place of its `{name}`.
    Path,
    /// Into the query string.
    Query,
    /// As a header.
    Header,
}

/// The request body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Body {
    /// The media type: `application/json`.
    pub media: String,
    /// The body's JSON Schema, as text, read from the file the mapping names.
    pub schema: Option<String>,
    /// Whether the call must send one.
    pub required: bool,
}

/// How the service authenticates a call.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Auth {
    /// `Authorization: Bearer <token>`.
    Bearer,
    /// `Authorization: Basic <user:password>`.
    Basic,
    /// A key in the header of this name.
    Header(String),
    /// A key in the query, under this name.
    Query(String),
    /// A scheme the wrapper does not carry, named as the mapping names it.
    Other(String),
}

/// Read the mapping at `file`. The schema files it names are read relative to it.
pub fn read_http(file: &Path) -> Result<Http, Diagnostic> {
    let text = fs::read_to_string(file)
        .map_err(|err| Diagnostic::new(file, format!("cannot read: {err}")))?;
    let doc: KdlDocument = text
        .parse()
        .map_err(|err| Diagnostic::new(file, format!("not valid KDL: {err}")))?;
    let line_of = |node: &KdlNode| text[..node.span().offset()].matches('\n').count() + 1;
    let mut http = Http {
        base: None,
        auths: Vec::new(),
        commands: BTreeMap::new(),
    };
    for node in doc.nodes() {
        let at = |what: String| Diagnostic::new(file, what).at_line(line_of(node));
        match node.name().value() {
            "base" => {
                http.base =
                    Some(first_arg(node).ok_or_else(|| at("`base` names no URL".to_string()))?);
            }
            "auth" => {
                let kind = first_arg(node).ok_or_else(|| at("`auth` names no kind".into()))?;
                let name = || {
                    prop(node, "name")
                        .ok_or_else(|| at(format!("`auth \"{kind}\"` names no `name=`")))
                };
                http.auths.push(match kind.as_str() {
                    "bearer" => Auth::Bearer,
                    "basic" => Auth::Basic,
                    "header" => Auth::Header(name()?),
                    "query" => Auth::Query(name()?),
                    other => Auth::Other(other.to_string()),
                });
            }
            "cmd" => read_cmd(
                node,
                &CommandPath::root(),
                file,
                &line_of,
                &mut http.commands,
            )?,
            other => return Err(at(format!("`{other}` is not a node of an HTTP mapping"))),
        }
    }
    Ok(http)
}

fn read_cmd(
    node: &KdlNode,
    parent: &CommandPath,
    file: &Path,
    line_of: &dyn Fn(&KdlNode) -> usize,
    out: &mut BTreeMap<CommandPath, Request>,
) -> Result<(), Diagnostic> {
    let at = |node: &KdlNode, what: String| Diagnostic::new(file, what).at_line(line_of(node));
    let name = first_arg(node).ok_or_else(|| at(node, "`cmd` names no command".into()))?;
    let path = parent.child(&name);
    let method = prop(node, "method")
        .ok_or_else(|| at(node, format!("`{path}` has no `method=`")))?
        .to_lowercase();
    let template =
        prop(node, "path").ok_or_else(|| at(node, format!("`{path}` has no `path=`")))?;
    let mut request = Request {
        method,
        path: template,
        params: Vec::new(),
        body: None,
    };
    for child in node.children().map(KdlDocument::nodes).unwrap_or_default() {
        let kind = child.name().value();
        match kind {
            "path" | "query" | "header" => {
                let wire = first_arg(child)
                    .ok_or_else(|| at(child, format!("`{path}`: `{kind}` names no parameter")))?;
                let (location, key) = match kind {
                    "path" => (Location::Path, "arg"),
                    "query" => (Location::Query, "flag"),
                    _ => (Location::Header, "flag"),
                };
                let param = prop(child, key).ok_or_else(|| {
                    at(
                        child,
                        format!("`{path}`: `{kind} \"{wire}\"` names no `{key}=`"),
                    )
                })?;
                request.params.push(Wire {
                    location,
                    name: wire,
                    param,
                });
            }
            "body" => {
                let media = first_arg(child)
                    .ok_or_else(|| at(child, format!("`{path}`: `body` names no media type")))?;
                let schema = match prop(child, "schema") {
                    Some(relative) => {
                        let schema_file = file
                            .parent()
                            .unwrap_or_else(|| Path::new("."))
                            .join(&relative);
                        Some(fs::read_to_string(&schema_file).map_err(|err| {
                            at(
                                child,
                                format!(
                                    "`{path}`: the body's schema {}: {err}",
                                    schema_file.display()
                                ),
                            )
                        })?)
                    }
                    None => None,
                };
                let required = child.entries().iter().any(|entry| {
                    entry.name().map(|n| n.value()) == Some("required")
                        && entry.value().as_bool() == Some(true)
                });
                request.body = Some(Body {
                    media,
                    schema,
                    required,
                });
            }
            "cmd" => read_cmd(child, &path, file, line_of, out)?,
            other => {
                return Err(at(
                    child,
                    format!("`{path}`: `{other}` is not a node of a request"),
                ));
            }
        }
    }
    if out.insert(path.clone(), request).is_some() {
        return Err(at(node, format!("`{path}` is mapped twice")));
    }
    Ok(())
}

fn first_arg(node: &KdlNode) -> Option<String> {
    node.entries()
        .iter()
        .find(|entry| entry.name().is_none())
        .and_then(|entry| entry.value().as_string().map(str::to_string))
}

fn prop(node: &KdlNode, name: &str) -> Option<String> {
    node.get(name)
        .and_then(|value| value.as_string())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn written(name: &str, text: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("nusage-http-{name}-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("schemas")).unwrap();
        std::fs::write(
            dir.join("schemas/body.schema.json"),
            r#"{"type": "object"}"#,
        )
        .unwrap();
        let file = dir.join("api.http.kdl");
        std::fs::write(&file, text).unwrap();
        file
    }

    #[test]
    fn the_mapping_is_read() {
        let file = written(
            "read",
            r#"base "https://example.com/v1"
auth "bearer"
auth "header" name="X-Api-Key"
cmd "list" method="GET" path="/pets" {
    query "limit" flag="limit"
    header "X-Request-Id" flag="x-request-id"
}
cmd "create" method="post" path="/pets" {
    body "application/json" schema="schemas/body.schema.json" required=#true
}
cmd "pets" method="get" path="/pets" {
    cmd "show" method="get" path="/pets/{petId}" {
        path "petId" arg="pet-id"
    }
}
"#,
        );
        let http = read_http(&file).unwrap();
        assert_eq!(http.base.as_deref(), Some("https://example.com/v1"));
        assert_eq!(http.auths, [Auth::Bearer, Auth::Header("X-Api-Key".into())]);
        let list = &http.commands[&CommandPath(vec!["list".into()])];
        assert_eq!(list.method, "get");
        assert_eq!(list.params.len(), 2);
        assert_eq!(list.params[1].location, Location::Header);
        assert_eq!(list.params[1].param, "x-request-id");
        let create = &http.commands[&CommandPath(vec!["create".into()])];
        let body = create.body.as_ref().unwrap();
        assert_eq!(body.media, "application/json");
        assert!(body.required);
        assert_eq!(body.schema.as_deref(), Some(r#"{"type": "object"}"#));
        let show = &http.commands[&CommandPath(vec!["pets".into(), "show".into()])];
        assert_eq!(show.path, "/pets/{petId}");
        assert_eq!(show.params[0].location, Location::Path);
        std::fs::remove_dir_all(file.parent().unwrap()).unwrap();
    }

    #[test]
    fn what_the_mapping_gets_wrong_names_its_line() {
        for (name, text, what) in [
            ("method", "cmd \"x\" path=\"/x\"\n", "no `method=`"),
            (
                "arg",
                "cmd \"x\" method=\"get\" path=\"/x\" {\n    path \"id\"\n}\n",
                "names no `arg=`",
            ),
            (
                "node",
                "cmd \"x\" method=\"get\" path=\"/x\" {\n    cookie \"c\"\n}\n",
                "not a node",
            ),
            (
                "schema",
                "cmd \"x\" method=\"post\" path=\"/x\" {\n    body \"text/plain\" schema=\"nope.json\"\n}\n",
                "nope.json",
            ),
        ] {
            let file = written(name, text);
            let err = read_http(&file).unwrap_err().to_string();
            assert!(err.contains(what), "{name}: {err}");
            std::fs::remove_dir_all(file.parent().unwrap()).unwrap();
        }
    }
}
