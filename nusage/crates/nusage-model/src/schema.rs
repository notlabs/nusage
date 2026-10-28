//! A JSON Schema as a Nushell type, with what JSON cannot carry: the schema an `output`
//! declares says what a binary writes, and this reads it the way a signature needs it. The
//! mapping is the obvious one: an object is a `record` of its properties in their order, an
//! array of objects a `table`, any other array a `list`, `integer` is `int`, `number` is
//! `float`, and a property the schema does not require is `oneof<T, nothing>`, filled with
//! `null` when absent so it is there to read. In the items of a list that is not a table,
//! where no cell path reaches to fill it, such a property is left out of the type instead,
//! since the type of a record says what every record has. A string with `format: date-time`
//! becomes a datetime, one with `contentEncoding: base64` becomes binary, and a number with
//! an `x-nu` vocabulary entry (`{"type": "duration", "unit": "ms"}`, also `filesize` and
//! `datetime`) becomes that, counting its unit. `anyOf`, `oneOf` and a list of types are
//! `oneof<…>`; `enum` and `const` take the type of their values; a local `$ref` is followed.
//! What this does not read is `any`: `allOf`, `not`, conditionals, `patternProperties`.

use serde_json::Value as Json;

use crate::{Conversion, NuType};

/// What a schema says about the value: its type, the optional properties to fill, and the
/// conversions, as [`crate::Structured`] carries them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Shape {
    pub ty: NuType,
    pub fills: Vec<Vec<String>>,
    pub conversions: Vec<Conversion>,
}

pub fn shape(schema: &str) -> Result<Shape, String> {
    let root: Json = serde_json::from_str(schema).map_err(|err| format!("not JSON: {err}"))?;
    let mut reader = Reader {
        root: &root,
        fills: Vec::new(),
        conversions: Vec::new(),
        refs: Vec::new(),
    };
    let ty = reader.node(&root, &Place::top())?;
    Ok(Shape {
        ty: NuType(ty),
        fills: reader.fills,
        conversions: reader.conversions,
    })
}

struct Reader<'a> {
    root: &'a Json,
    fills: Vec<Vec<String>>,
    conversions: Vec<Conversion>,
    /// The `$ref`s being followed, to stop at a cycle.
    refs: Vec<String>,
}

/// Where in the value a schema node sits: its cell path, whether a list stands between it
/// and the top (where no cell path reaches), and whether it may be null.
struct Place {
    path: Vec<String>,
    in_list: bool,
    nullable: bool,
}

impl Place {
    fn top() -> Self {
        Place {
            path: Vec::new(),
            in_list: false,
            nullable: false,
        }
    }

    fn field(&self, name: &str, nullable: bool) -> Self {
        let mut path = self.path.clone();
        path.push(name.to_string());
        Place {
            path,
            in_list: self.in_list,
            nullable: self.nullable || nullable,
        }
    }

    fn item(&self) -> Self {
        Place {
            path: self.path.clone(),
            in_list: true,
            nullable: false,
        }
    }

    fn describe(&self) -> String {
        if self.path.is_empty() {
            "the value".to_string()
        } else {
            format!("`{}`", self.path.join("."))
        }
    }
}

impl Reader<'_> {
    fn node(&mut self, schema: &Json, place: &Place) -> Result<String, String> {
        let Some(object) = schema.as_object() else {
            // `true` and `false` schemas, or nonsense.
            return Ok("any".to_string());
        };
        if let Some(reference) = object.get("$ref").and_then(Json::as_str) {
            return self.reference(reference, place);
        }
        for union in ["anyOf", "oneOf"] {
            if let Some(members) = object.get(union).and_then(Json::as_array) {
                return self.union(members, place);
            }
        }
        let types: Vec<&str> = match object.get("type") {
            Some(Json::String(one)) => vec![one.as_str()],
            Some(Json::Array(many)) => many.iter().filter_map(Json::as_str).collect(),
            _ => Vec::new(),
        };
        if types.len() > 1 {
            let nullable = types.contains(&"null");
            let mut members = Vec::new();
            for ty in &types {
                let mut one = object.clone();
                one.insert("type".into(), Json::String(ty.to_string()));
                let place = Place {
                    path: place.path.clone(),
                    in_list: place.in_list,
                    nullable: place.nullable || nullable,
                };
                members.push(self.node(&Json::Object(one), &place)?);
            }
            return Ok(oneof(members));
        }
        if let Some(values) = object.get("enum").and_then(Json::as_array) {
            return Ok(oneof(values.iter().map(literal_type).collect()));
        }
        if let Some(value) = object.get("const") {
            return Ok(literal_type(value));
        }
        let ty = types.first().copied();
        if let Some(nu) = object.get("x-nu") {
            return self.counted(nu, ty, place);
        }
        match ty {
            Some("object") => self.object(object, place),
            Some("array") => self.array(object, place),
            Some("string") => {
                if object.get("format").and_then(Json::as_str) == Some("date-time") {
                    self.convert(place, "datetime", None);
                    Ok("datetime".to_string())
                } else if object.get("contentEncoding").and_then(Json::as_str) == Some("base64") {
                    self.convert(place, "base64", None);
                    Ok("binary".to_string())
                } else {
                    Ok("string".to_string())
                }
            }
            Some("integer") => Ok("int".to_string()),
            Some("number") => Ok("float".to_string()),
            Some("boolean") => Ok("bool".to_string()),
            Some("null") => Ok("nothing".to_string()),
            Some(other) => Err(format!("{}: unknown type `{other}`", place.describe())),
            None if object.contains_key("properties") => self.object(object, place),
            None if object.contains_key("items") => self.array(object, place),
            None => Ok("any".to_string()),
        }
    }

    fn reference(&mut self, reference: &str, place: &Place) -> Result<String, String> {
        let Some(pointer) = reference.strip_prefix('#') else {
            return Err(format!(
                "{}: `$ref` {reference:?} is not local; only `#/...` is followed",
                place.describe()
            ));
        };
        if self.refs.iter().any(|seen| seen == reference) {
            // A recursive schema: the value has no finite type.
            return Ok("any".to_string());
        }
        let target = self
            .root
            .pointer(pointer)
            .ok_or_else(|| format!("{}: `$ref` {reference:?} points nowhere", place.describe()))?
            .clone();
        self.refs.push(reference.to_string());
        let ty = self.node(&target, place);
        self.refs.pop();
        ty
    }

    fn union(&mut self, members: &[Json], place: &Place) -> Result<String, String> {
        let nullable = members
            .iter()
            .any(|member| member.get("type").and_then(Json::as_str) == Some("null"));
        let place = Place {
            path: place.path.clone(),
            in_list: place.in_list,
            nullable: place.nullable || nullable,
        };
        let mut types = Vec::new();
        for member in members {
            types.push(self.node(member, &place)?);
        }
        Ok(oneof(types))
    }

    /// `x-nu`: a number counting units of a duration, a file size or a datetime.
    fn counted(&mut self, nu: &Json, ty: Option<&str>, place: &Place) -> Result<String, String> {
        let kind = nu
            .get("type")
            .and_then(Json::as_str)
            .ok_or_else(|| format!("{}: `x-nu` names no type", place.describe()))?;
        let unit = nu
            .get("unit")
            .and_then(Json::as_str)
            .ok_or_else(|| format!("{}: `x-nu` names no unit", place.describe()))?;
        if !matches!(ty, Some("integer" | "number")) {
            return Err(format!(
                "{}: `x-nu` converts a number, and this is {}",
                place.describe(),
                ty.unwrap_or("untyped")
            ));
        }
        let units: &[&str] = match kind {
            "duration" => &["ns", "us", "ms", "sec", "min", "hr", "day", "wk"],
            "datetime" => &["ns", "us", "ms", "sec"],
            "filesize" => &[
                "b", "kB", "MB", "GB", "TB", "PB", "EB", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB",
            ],
            other => {
                return Err(format!(
                    "{}: `x-nu` type `{other}` is not duration, filesize or datetime",
                    place.describe()
                ));
            }
        };
        if !units.contains(&unit) {
            return Err(format!(
                "{}: `{unit}` is not a unit of a {kind}; one of {}",
                place.describe(),
                units.join(", ")
            ));
        }
        self.convert(place, kind, Some(unit));
        Ok(kind.to_string())
    }

    fn object(
        &mut self,
        object: &serde_json::Map<String, Json>,
        place: &Place,
    ) -> Result<String, String> {
        let Some(properties) = object.get("properties").and_then(Json::as_object) else {
            return Ok("record".to_string());
        };
        let required: Vec<&str> = object
            .get("required")
            .and_then(Json::as_array)
            .map(|names| names.iter().filter_map(Json::as_str).collect())
            .unwrap_or_default();
        let mut columns = Vec::new();
        for (name, property) in properties {
            let optional = !required.contains(&name.as_str());
            let field = place.field(name, optional);
            let ty = self.node(property, &field)?;
            if !optional {
                columns.push(format!("{}: {ty}", column(name)));
            } else if !field.in_list {
                self.fills.push(field.path.clone());
                let ty = oneof(vec![ty, "nothing".to_string()]);
                columns.push(format!("{}: {ty}", column(name)));
            }
            // An optional property no fill reaches is left out: a record may carry fields
            // its type does not name, and must carry the ones it does.
        }
        Ok(format!("record<{}>", columns.join(", ")))
    }

    fn array(
        &mut self,
        object: &serde_json::Map<String, Json>,
        place: &Place,
    ) -> Result<String, String> {
        let Some(items) = object.get("items") else {
            return Ok("list<any>".to_string());
        };
        // A column of a table is a cell path, as a record's field is; the items of any
        // other list are not.
        let rows = self.is_object(items) && !place.in_list;
        let item_place = if rows {
            place.field_less()
        } else {
            place.item()
        };
        let before = self.conversions.len();
        let ty = self.node(items, &item_place)?;
        if !rows && self.conversions.len() > before {
            let what = self.conversions[before].ty.clone();
            return Err(format!(
                "{}: a {what} inside a list cannot be converted after decoding; JSON delivers \
                 it as it is",
                place.describe()
            ));
        }
        Ok(if rows {
            ty.replacen("record<", "table<", 1)
        } else {
            format!("list<{ty}>")
        })
    }

    /// Whether the schema describes an object, following a local `$ref`.
    fn is_object(&self, schema: &Json) -> bool {
        let mut seen = 0;
        let mut schema = schema;
        while let Some(reference) = schema.get("$ref").and_then(Json::as_str) {
            let Some(target) = reference
                .strip_prefix('#')
                .and_then(|pointer| self.root.pointer(pointer))
            else {
                return false;
            };
            schema = target;
            seen += 1;
            if seen > 32 {
                return false;
            }
        }
        schema.get("type").and_then(Json::as_str) == Some("object")
            || schema.get("properties").is_some()
    }

    fn convert(&mut self, place: &Place, ty: &str, unit: Option<&str>) {
        self.conversions.push(Conversion {
            path: place.path.clone(),
            ty: ty.to_string(),
            unit: unit.map(str::to_string),
            nullable: place.nullable,
        });
    }
}

impl Place {
    /// The rows of a table: the same cell paths, nothing between them and the top.
    fn field_less(&self) -> Self {
        Place {
            path: self.path.clone(),
            in_list: self.in_list,
            nullable: false,
        }
    }
}

/// `oneof<a, b>` of the distinct members, or the one member.
fn oneof(members: Vec<String>) -> String {
    let mut distinct: Vec<String> = Vec::new();
    for member in members {
        // A union of unions flattens.
        let parts: Vec<String> = match member
            .strip_prefix("oneof<")
            .and_then(|r| r.strip_suffix('>'))
        {
            Some(inner) => split_top_level(inner),
            None => vec![member],
        };
        for part in parts {
            if !distinct.contains(&part) {
                distinct.push(part);
            }
        }
    }
    if distinct.len() == 1 {
        distinct.pop().unwrap()
    } else {
        format!("oneof<{}>", distinct.join(", "))
    }
}

/// The members of a `oneof<…>` body, split at the commas outside any nested `<…>`.
fn split_top_level(inner: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut depth = 0;
    let mut current = String::new();
    for c in inner.chars() {
        match c {
            '<' => depth += 1,
            '>' => depth -= 1,
            ',' if depth == 0 => {
                parts.push(current.trim().to_string());
                current.clear();
                continue;
            }
            _ => {}
        }
        current.push(c);
    }
    if !current.trim().is_empty() {
        parts.push(current.trim().to_string());
    }
    parts
}

fn literal_type(value: &Json) -> String {
    match value {
        Json::String(_) => "string",
        Json::Number(n) if n.is_i64() || n.is_u64() => "int",
        Json::Number(_) => "float",
        Json::Bool(_) => "bool",
        Json::Null => "nothing",
        Json::Array(_) => "list<any>",
        Json::Object(_) => "record",
    }
    .to_string()
}

/// A record column as a type writes it: bare when it is a word, else quoted.
fn column(name: &str) -> String {
    nusage_nu::word(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ty(schema: &str) -> String {
        shape(schema).unwrap().ty.0
    }

    #[test]
    fn scalars_and_containers() {
        assert_eq!(ty(r#"{"type": "integer"}"#), "int");
        assert_eq!(ty(r#"{"type": "number"}"#), "float");
        assert_eq!(
            ty(r#"{"type": "array", "items": {"type": "string"}}"#),
            "list<string>"
        );
        assert_eq!(ty(r#"{"type": "array"}"#), "list<any>");
        assert_eq!(ty(r#"{"type": "object"}"#), "record");
        assert_eq!(ty("true"), "any");
    }

    #[test]
    fn objects_are_records_and_rows_are_tables() {
        let schema = r#"{"type": "object", "properties": {"ok": {"type": "boolean"}, "name": {"type": "string"}}, "required": ["ok"]}"#;
        let shape = shape(schema).unwrap();
        assert_eq!(shape.ty.0, "record<ok: bool, name: oneof<string, nothing>>");
        assert_eq!(shape.fills, vec![vec!["name".to_string()]]);
        let rows = format!(r#"{{"type": "array", "items": {schema}}}"#);
        assert_eq!(ty(&rows), "table<ok: bool, name: oneof<string, nothing>>");
        let referenced = format!(
            r##"{{"$defs": {{"row": {schema}}}, "type": "array", "items": {{"$ref": "#/$defs/row"}}}}"##
        );
        assert_eq!(
            ty(&referenced),
            "table<ok: bool, name: oneof<string, nothing>>"
        );
    }

    #[test]
    fn an_optional_property_no_fill_reaches_is_left_out() {
        // A list of strings or records, as mise writes a task's dependencies: the records
        // are no table's rows, so `args` cannot be filled, and a type naming it would be
        // wrong for every record that lacks it.
        let schema = r#"{"type": "array", "items": {"anyOf": [{"type": "string"}, {"type": "object",
            "required": ["task"], "properties": {"task": {"type": "string"},
            "args": {"type": "array", "items": {"type": "string"}}}}]}}"#;
        let listed = shape(schema).unwrap();
        assert_eq!(listed.ty.0, "list<oneof<string, record<task: string>>>");
        assert!(listed.fills.is_empty(), "{:?}", listed.fills);
        // A table nested in a record is still filled, column by column.
        let nested = r#"{"type": "object", "required": ["rows"], "properties": {"rows": {"type":
            "array", "items": {"type": "object", "required": ["id"], "properties": {"id": {"type":
            "integer"}, "note": {"type": "string"}}}}}}"#;
        let tabled = shape(nested).unwrap();
        assert_eq!(
            tabled.ty.0,
            "record<rows: table<id: int, note: oneof<string, nothing>>>"
        );
        assert_eq!(
            tabled.fills,
            vec![vec!["rows".to_string(), "note".to_string()]]
        );
    }

    #[test]
    fn what_json_cannot_carry_is_converted() {
        let schema = r#"{"type": "object", "required": ["took", "at", "size", "data"], "properties": {
            "took": {"type": "integer", "x-nu": {"type": "duration", "unit": "ms"}},
            "at": {"type": "string", "format": "date-time"},
            "size": {"type": "integer", "x-nu": {"type": "filesize", "unit": "kB"}},
            "data": {"type": "string", "contentEncoding": "base64"},
            "seen": {"type": "integer", "x-nu": {"type": "datetime", "unit": "sec"}}}}"#;
        let shape = shape(schema).unwrap();
        assert_eq!(
            shape.ty.0,
            "record<took: duration, at: datetime, size: filesize, data: binary, seen: oneof<datetime, nothing>>"
        );
        let conversions: Vec<(String, String, Option<String>, bool)> = shape
            .conversions
            .iter()
            .map(|c| (c.path.join("."), c.ty.clone(), c.unit.clone(), c.nullable))
            .collect();
        assert_eq!(
            conversions,
            vec![
                ("took".into(), "duration".into(), Some("ms".into()), false),
                ("at".into(), "datetime".into(), None, false),
                ("size".into(), "filesize".into(), Some("kB".into()), false),
                ("data".into(), "base64".into(), None, false),
                ("seen".into(), "datetime".into(), Some("sec".into()), true),
            ]
        );
    }

    #[test]
    fn unions_refs_and_enums() {
        assert_eq!(
            ty(r#"{"type": ["string", "null"]}"#),
            "oneof<string, nothing>"
        );
        assert_eq!(
            ty(r#"{"anyOf": [{"type": "integer"}, {"type": "string"}, {"type": "integer"}]}"#),
            "oneof<int, string>"
        );
        assert_eq!(ty(r#"{"enum": ["a", "b"]}"#), "string");
        assert_eq!(ty(r#"{"const": 3}"#), "int");
        let defs = r##"{"$defs": {"id": {"type": "integer"}}, "type": "object", "required": ["id"], "properties": {"id": {"$ref": "#/$defs/id"}}}"##;
        assert_eq!(ty(defs), "record<id: int>");
        let cyclic = r##"{"$defs": {"node": {"type": "object", "required": ["next"], "properties": {"next": {"$ref": "#/$defs/node"}}}}, "$ref": "#/$defs/node"}"##;
        assert_eq!(ty(cyclic), "record<next: any>");
    }

    #[test]
    fn what_cannot_be_read_is_an_error() {
        assert!(
            shape(r#"{"type": "array", "items": {"type": "string", "format": "date-time"}}"#)
                .is_err()
        );
        assert!(
            shape(r#"{"type": "string", "x-nu": {"type": "duration", "unit": "ms"}}"#).is_err()
        );
        assert!(
            shape(r#"{"type": "integer", "x-nu": {"type": "duration", "unit": "parsecs"}}"#)
                .is_err()
        );
        assert!(shape(r##"{"$ref": "https://example.com/x.json"}"##).is_err());
    }
}
