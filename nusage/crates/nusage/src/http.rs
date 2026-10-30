//! The HTTP target: one `export def` per command of a service described by a spec with an
//! HTTP mapping beside it. The commands are named as a binary's are, `<name> <command>`
//! with `main` for the root, so `use <name>.nu *` names them as the spec does. A wrapper's
//! body hands `nusage request` what the mapping says the call sends, the path parameters,
//! query and headers from its typed parameters and the body from its input, and decodes the
//! response as a binary wrapper decodes an output, with the same helper and the same hold to
//! the schema when decoding fails. The root says where the service is.

use nusage_model::{Auth, Body, Command, CommandTree, Execution, Location, Request, Service};
use nusage_nu::{CommandName, Def, Expr, Ident, Item, Module, Params, Stmt, SyntaxError, Type};

use crate::binary::{DECODED, HELPERS, call, decode_stages};
use crate::common::{Target, attr_usage_alias, doc_of, nu_params, usage_attrs};

/// The helpers that make a request, carried by every service module.
const REQUEST: &str = include_str!("http-helpers.nu");

/// The module for a service: the helpers, then a wrapper per command.
pub fn module(tree: &CommandTree) -> Result<Module, SyntaxError> {
    let service = tree.service.as_ref().ok_or_else(|| {
        SyntaxError("the HTTP target wraps a spec with an HTTP mapping".to_string())
    })?;
    let mut items = vec![
        Item::Verbatim(HELPERS.to_string()),
        Item::Verbatim(REQUEST.to_string()),
    ];
    if tree.commands.iter().any(|command| {
        command
            .structured
            .as_ref()
            .is_some_and(|s| s.schema.is_some())
    }) {
        items.push(Item::Verbatim(DECODED.to_string()));
    }
    for command in &tree.commands {
        let def = wrapper(tree, service, command)
            .map_err(|err| SyntaxError(format!("`{} {}`: {err}", tree.bin, command.path)))?;
        items.push(Item::Def(def));
    }
    Ok(Module {
        preamble: vec![attr_usage_alias()?],
        items,
    })
}

fn wrapper(tree: &CommandTree, service: &Service, command: &Command) -> Result<Def, SyntaxError> {
    let name = if command.path.is_root() {
        "main".to_string()
    } else {
        format!("{} {}", tree.bin, command.path)
    };
    let params = command
        .positionals
        .iter()
        .chain(command.flags.iter())
        .map(|param| nu_params(param, Target::Binary))
        .collect::<Result<Vec<_>, _>>()?
        .concat();
    let base = match &service.base {
        Some(base) => Expr::Str(base.clone()),
        None => Expr::Raw("null".to_string()),
    };
    let request = match &command.execution {
        Execution::Request(request) => request,
        Execution::Service => {
            // The root: where the service is, as the wrappers find it.
            return Ok(Def {
                export: true,
                doc: doc_of(command),
                attrs: usage_attrs(command)?,
                name: CommandName::new(name)?,
                params: Params::new(params)?,
                io: Some((Type::new("nothing")?, Type::new("string")?)),
                body: vec![Stmt::Pipeline(vec![call(
                    "nusage base",
                    vec![Expr::Str(tree.bin.clone()), base],
                )?])],
            });
        }
        Execution::Script(_) | Execution::External => {
            return Err(SyntaxError(
                "not a request of the service; the HTTP target only wraps those".to_string(),
            ));
        }
    };
    let input = match &request.body {
        Some(Body {
            ty: Some(ty),
            required,
            ..
        }) => {
            if *required {
                Type::new(ty.as_str())?
            } else {
                Type::new(format!("oneof<{}, nothing>", ty.as_str()))?
            }
        }
        Some(Body { ty: None, .. }) => Type::new("any")?,
        None => Type::new("nothing")?,
    };
    let output = match &command.output {
        Some(output) => Type::new(output.as_str())?,
        None => Type::new("string")?,
    };
    // Then the decoding, as a binary wrapper's. A decoded output binds the response first,
    // and a `let` does not pass the wrapper's input on, so the body is bound before it.
    let body = match &command.structured {
        Some(structured) if structured.schema.is_some() => {
            let schema: serde_json::Value =
                serde_json::from_str(structured.schema.as_deref().unwrap_or_default())
                    .map_err(|err| SyntaxError(format!("the output's schema: {err}")))?;
            let text = Ident::new("text")?;
            let mut args = vec![
                Expr::Var(text.clone()),
                Expr::Str(schema.to_string()),
                Expr::Closure(Box::new(Expr::Pipeline(decode_stages(structured)?))),
            ];
            if structured.framing == nusage_model::Framing::Jsonl {
                args.push(Expr::Str("--lines".into()));
            }
            let mut body = Vec::new();
            let carried = if request.body.is_some() {
                let bound = Ident::new("body")?;
                body.push(Stmt::Let {
                    name: bound.clone(),
                    value: Expr::Var(Ident::new("in")?),
                });
                bound
            } else {
                Ident::new("in")?
            };
            let run = call(
                "nusage request",
                vec![request_record(tree, service, base, request, carried)?],
            )?;
            body.push(Stmt::Let {
                name: text,
                value: run,
            });
            body.push(Stmt::Pipeline(vec![call("nusage decoded", args)?]));
            body
        }
        Some(structured) => {
            let run = call(
                "nusage request",
                vec![request_record(
                    tree,
                    service,
                    base,
                    request,
                    Ident::new("in")?,
                )?],
            )?;
            let mut stages = vec![run];
            stages.extend(decode_stages(structured)?);
            vec![Stmt::Pipeline(stages)]
        }
        None => vec![Stmt::Pipeline(vec![call(
            "nusage request",
            vec![request_record(
                tree,
                service,
                base,
                request,
                Ident::new("in")?,
            )?],
        )?])],
    };
    Ok(Def {
        export: true,
        doc: doc_of(command),
        attrs: usage_attrs(command)?,
        name: CommandName::new(name)?,
        params: Params::new(params)?,
        io: Some((input, output)),
        body,
    })
}

/// What `nusage request` is handed: the service and where it is, how it authenticates, the
/// method and path, and the parameters by where they go, each as the variable that carries
/// it; the body as `carried`, the input or the variable bound to it, with its media type,
/// when the call sends one.
fn request_record(
    tree: &CommandTree,
    service: &Service,
    base: Expr,
    request: &Request,
    carried: Ident,
) -> Result<Expr, SyntaxError> {
    let auths = service
        .auths
        .iter()
        .map(|auth| {
            let (kind, name) = match auth {
                Auth::Bearer => ("bearer", None),
                Auth::Basic => ("basic", None),
                Auth::Header(name) => ("header", Some(name)),
                Auth::Query(name) => ("query", Some(name)),
                Auth::Other(kind) => (kind.as_str(), None),
            };
            let mut fields = vec![("kind".to_string(), Expr::Str(kind.to_string()))];
            if let Some(name) = name {
                fields.push(("name".to_string(), Expr::Str(name.clone())));
            }
            Expr::Record(fields)
        })
        .collect();
    let at = |location: Location| -> Result<Expr, SyntaxError> {
        request
            .params
            .iter()
            .filter(|wire| wire.location == location)
            .map(|wire| Ok((wire.name.clone(), Expr::Var(Ident::new(&wire.var)?))))
            .collect::<Result<Vec<_>, SyntaxError>>()
            .map(Expr::Record)
    };
    let mut fields = vec![
        ("service".to_string(), Expr::Str(tree.bin.clone())),
        ("base".to_string(), base),
        ("auth".to_string(), Expr::List(auths)),
        ("method".to_string(), Expr::Str(request.method.clone())),
        ("path".to_string(), Expr::Str(request.path.clone())),
        ("params".to_string(), at(Location::Path)?),
        ("query".to_string(), at(Location::Query)?),
        ("headers".to_string(), at(Location::Header)?),
    ];
    if let Some(body) = &request.body {
        fields.push(("body".to_string(), Expr::Var(carried)));
        fields.push(("media".to_string(), Expr::Str(body.media.clone())));
    }
    Ok(Expr::Record(fields))
}
