//! A schema read as a Nushell type, with what JSON cannot carry: the fields to fill and the
//! conversions to run after decoding. The crate's documentation says how a schema maps to a
//! type.

use serde::Serialize;
use serde_json::Value as Json;

/// A Nushell type as text: `record<id: int, at: datetime>`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct NuType(pub String);

impl NuType {
    /// The type as text.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A property the schema does not require, filled with `null` where its record leaves it
/// out.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Fill {
    /// The cell path of the field.
    pub path: Vec<String>,
    /// Where on the way to the record `null` may stand instead, as the lengths of the
    /// prefixes of `path` that may be `null`, shortest first. A `null` is left as it is,
    /// with no field under it to fill.
    pub nullable: Vec<usize>,
}

/// A value JSON delivers as text or a number, converted to the declared type at a cell path
/// (empty for the whole value).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Conversion {
    /// The cell path of the value.
    pub path: Vec<String>,
    /// `datetime`, `duration` or `filesize`; `binary` for text taken as bytes, `base64`
    /// for text decoded.
    pub ty: String,
    /// For a number: what it counts, as the schema's `x-nu` says, spelled as in a Nushell
    /// literal (`ms`, `sec`, `kB`). `None` for text, such as an ISO 8601 datetime.
    pub unit: Option<String>,
    /// Where on the way to the value `null` may stand instead, as the lengths of the
    /// prefixes of `path` that may be `null`, shortest first: the whole path for the value
    /// itself. A `null` is left as it is, with nothing under it to convert.
    pub nullable: Vec<usize>,
}

/// What a schema says about the value: its type, the optional properties to fill, and the
/// conversions, in the order to run them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Shape {
    /// The Nushell type.
    pub ty: NuType,
    /// The fills, a record's own field before the fields under it.
    pub fills: Vec<Fill>,
    /// The conversions, in schema order.
    pub conversions: Vec<Conversion>,
}

/// Why a schema cannot be read as a shape.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum Error {
    /// The text is not JSON.
    #[error("not JSON: {0}")]
    Json(String),
    /// A `type` the dialect does not have.
    #[error("{place}: unknown type `{ty}`")]
    UnknownType {
        /// Where in the value.
        place: String,
        /// The type as written.
        ty: String,
    },
    /// A `$ref` into another document.
    #[error("{place}: `$ref` {reference:?} is not local; only `#/...` is followed")]
    ForeignReference {
        /// Where in the value.
        place: String,
        /// The reference as written.
        reference: String,
    },
    /// A `$ref` that names nothing in the document.
    #[error("{place}: `$ref` {reference:?} points nowhere")]
    DanglingReference {
        /// Where in the value.
        place: String,
        /// The reference as written.
        reference: String,
    },
    /// A conversion inside a union of several shapes, where which shape the value has is
    /// not known after decoding.
    #[error(
        "{place}: a {what} inside a union of several shapes cannot be converted after \
         decoding; which shape the value has is not known"
    )]
    ConvertedInUnion {
        /// Where in the value.
        place: String,
        /// The conversion's type.
        what: String,
    },
    /// A conversion inside a list that is not a table, where no cell path reaches.
    #[error(
        "{place}: a {what} inside a list cannot be converted after decoding; JSON delivers \
         it as it is"
    )]
    ConvertedInList {
        /// Where in the value.
        place: String,
        /// The conversion's type.
        what: String,
    },
    /// An `allOf` whose branches cannot all hold at once.
    #[error(
        "{place}: the branches of `allOf` disagree on `{keyword}`, so no value satisfies all \
         of them"
    )]
    Unsatisfiable {
        /// Where in the value.
        place: String,
        /// The keyword the branches set differently.
        keyword: String,
    },
    /// An `x-nu` the vocabulary does not allow.
    #[error("{place}: {why}")]
    Counted {
        /// Where in the value.
        place: String,
        /// What is wrong with it.
        why: CountedError,
    },
}

/// What an `x-nu` got wrong.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum CountedError {
    /// No `type`.
    #[error("`x-nu` names no type")]
    NoType,
    /// No `unit`.
    #[error("`x-nu` names no unit")]
    NoUnit,
    /// On a schema that is not a number's.
    #[error("`x-nu` converts a number, and this is {0}")]
    NotANumber(String),
    /// A `type` that is not duration, filesize or datetime.
    #[error("`x-nu` type `{0}` is not duration, filesize or datetime")]
    UnknownKind(String),
    /// A `unit` the type does not count in.
    #[error("`{unit}` is not a unit of a {kind}; one of {}", units.join(", "))]
    UnknownUnit {
        /// The `x-nu` type.
        kind: String,
        /// The unit as written.
        unit: String,
        /// The units the type counts in.
        units: Vec<String>,
    },
}

/// The units a duration counts in, as Nushell spells them.
pub const UNITS_OF_DURATION: &[&str] = &["ns", "us", "ms", "sec", "min", "hr", "day", "wk"];
/// The units a datetime counts in, since the Unix epoch.
pub const UNITS_OF_DATETIME: &[&str] = &["ns", "us", "ms", "sec"];
/// The units a file size counts in, as Nushell spells them.
pub const UNITS_OF_FILESIZE: &[&str] = &[
    "b", "kB", "MB", "GB", "TB", "PB", "EB", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB",
];

/// The shape of the schema given as JSON text.
pub fn shape(schema: &str) -> Result<Shape, Error> {
    let root: Json = serde_json::from_str(schema).map_err(|err| Error::Json(err.to_string()))?;
    shape_of(&root)
}

/// The shape of the schema.
pub fn shape_of(schema: &Json) -> Result<Shape, Error> {
    let mut reader = Reader {
        root: schema,
        fills: Vec::new(),
        conversions: Vec::new(),
        refs: Vec::new(),
    };
    let ty = reader.node(schema, &Place::top())?;
    Ok(Shape {
        ty: NuType(ty),
        fills: reader.fills,
        conversions: reader.conversions,
    })
}

struct Reader<'a> {
    root: &'a Json,
    fills: Vec<Fill>,
    conversions: Vec<Conversion>,
    /// The `$ref`s being followed, to stop at a cycle.
    refs: Vec<String>,
}
/// Where in the value a schema node sits: its cell path, whether a list or a union of
/// several shapes stands between it and the top (where no cell path reaches, or not for
/// every value), and the prefixes of its path that may be null, by length, itself or what
/// it sits in.
struct Place {
    path: Vec<String>,
    in_list: bool,
    in_union: bool,
    nullable: Vec<usize>,
}

impl Place {
    fn top() -> Self {
        Place {
            path: Vec::new(),
            in_list: false,
            in_union: false,
            nullable: Vec::new(),
        }
    }

    /// Whether a cell path reaches this place in every value the schema describes.
    fn reached(&self) -> bool {
        !self.in_list && !self.in_union
    }

    fn field(&self, name: &str, nullable: bool) -> Self {
        let mut path = self.path.clone();
        path.push(name.to_string());
        let mut place = Place {
            path,
            in_list: self.in_list,
            in_union: self.in_union,
            nullable: self.nullable.clone(),
        };
        if nullable {
            place.nullable.push(place.path.len());
        }
        place
    }

    /// The same place, where the value itself may be null.
    fn or_null(&self, nullable: bool) -> Self {
        let mut nulls = self.nullable.clone();
        if nullable && nulls.last() != Some(&self.path.len()) {
            nulls.push(self.path.len());
        }
        Place {
            path: self.path.clone(),
            in_list: self.in_list,
            in_union: self.in_union,
            nullable: nulls,
        }
    }

    fn item(&self) -> Self {
        Place {
            path: self.path.clone(),
            in_list: true,
            in_union: self.in_union,
            nullable: Vec::new(),
        }
    }

    /// The same place, as one member of a union of several shapes sees it.
    fn member(&self) -> Self {
        Place {
            path: self.path.clone(),
            in_list: self.in_list,
            in_union: true,
            nullable: self.nullable.clone(),
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
    fn node(&mut self, schema: &Json, place: &Place) -> Result<String, Error> {
        let Some(object) = schema.as_object() else {
            // `true` and `false` schemas, or nonsense.
            return Ok("any".to_string());
        };
        if object.contains_key("allOf") {
            let merged = self.merged(object, place)?;
            return self.node(&merged, place);
        }
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
            let place = place.or_null(nullable);
            let place = if types.iter().filter(|ty| **ty != "null").count() > 1 {
                place.member()
            } else {
                place
            };
            let before = self.conversions.len();
            let mut members = Vec::new();
            for ty in &types {
                let mut one = object.clone();
                one.insert("type".into(), Json::String(ty.to_string()));
                members.push(self.node(&Json::Object(one), &place)?);
            }
            self.converted_in_union(&place, before)?;
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
            Some(other) => Err(Error::UnknownType {
                place: place.describe(),
                ty: other.to_string(),
            }),
            None if object.contains_key("properties") => self.object(object, place),
            None if object.contains_key("items") => self.array(object, place),
            None => Ok("any".to_string()),
        }
    }

    fn reference(&mut self, reference: &str, place: &Place) -> Result<String, Error> {
        let Some(pointer) = reference.strip_prefix('#') else {
            return Err(Error::ForeignReference {
                place: place.describe(),
                reference: reference.to_string(),
            });
        };
        if self.refs.iter().any(|seen| seen == reference) {
            // A recursive schema: the value has no finite type.
            return Ok("any".to_string());
        }
        let target = self
            .root
            .pointer(pointer)
            .ok_or_else(|| Error::DanglingReference {
                place: place.describe(),
                reference: reference.to_string(),
            })?
            .clone();
        self.refs.push(reference.to_string());
        let ty = self.node(&target, place);
        self.refs.pop();
        ty
    }

    /// The one schema an `allOf` and the keywords beside it describe together: every branch
    /// holds, so the properties are all of theirs, a property several describe is what they
    /// say together, the required names are all of theirs, and the type is what every branch
    /// that names one allows. A keyword the reader reads that two branches set differently
    /// is an error: no value has two formats. What the reader does not read is left out,
    /// and a branch that refers to itself adds nothing on the second visit.
    fn merged(&self, object: &serde_json::Map<String, Json>, place: &Place) -> Result<Json, Error> {
        let mut merged = serde_json::Map::new();
        let mut seen = Vec::new();
        self.merge_into(&mut merged, &Json::Object(object.clone()), place, &mut seen)?;
        Ok(Json::Object(merged))
    }

    fn merge_into(
        &self,
        into: &mut serde_json::Map<String, Json>,
        schema: &Json,
        place: &Place,
        seen: &mut Vec<String>,
    ) -> Result<(), Error> {
        let Some(object) = schema.as_object() else {
            // `true` constrains nothing; `false` is read as nothing too.
            return Ok(());
        };
        let unsatisfiable = |keyword: &str| Error::Unsatisfiable {
            place: place.describe(),
            keyword: keyword.to_string(),
        };
        if let Some(reference) = object.get("$ref").and_then(Json::as_str) {
            let Some(pointer) = reference.strip_prefix('#') else {
                return Err(Error::ForeignReference {
                    place: place.describe(),
                    reference: reference.to_string(),
                });
            };
            if !seen.iter().any(|visited| visited == reference) {
                let target = self
                    .root
                    .pointer(pointer)
                    .ok_or_else(|| Error::DanglingReference {
                        place: place.describe(),
                        reference: reference.to_string(),
                    })?
                    .clone();
                seen.push(reference.to_string());
                self.merge_into(into, &target, place, seen)?;
                seen.pop();
            }
        }
        if let Some(branches) = object.get("allOf").and_then(Json::as_array) {
            for branch in branches {
                self.merge_into(into, branch, place, seen)?;
            }
        }
        for (keyword, value) in object {
            match keyword.as_str() {
                "$ref" | "allOf" => {}
                "properties" => {
                    let Some(properties) = value.as_object() else {
                        continue;
                    };
                    let known = into
                        .entry("properties")
                        .or_insert_with(|| Json::Object(serde_json::Map::new()));
                    let Some(known) = known.as_object_mut() else {
                        continue;
                    };
                    for (name, property) in properties {
                        match known.get(name) {
                            None => {
                                known.insert(name.clone(), property.clone());
                            }
                            Some(before) if before == property => {}
                            Some(before) => {
                                // What both say: read as an `allOf` of its own.
                                let both = serde_json::json!({"allOf": [before, property]});
                                known.insert(name.clone(), both);
                            }
                        }
                    }
                }
                "required" => {
                    let Some(names) = value.as_array() else {
                        continue;
                    };
                    let known = into
                        .entry("required")
                        .or_insert_with(|| Json::Array(Vec::new()));
                    if let Some(known) = known.as_array_mut() {
                        for name in names {
                            if !known.contains(name) {
                                known.push(name.clone());
                            }
                        }
                    }
                }
                "type" => {
                    let allowed: Vec<Json> = match value {
                        Json::String(_) => vec![value.clone()],
                        Json::Array(many) => many.clone(),
                        _ => continue,
                    };
                    let kept: Vec<Json> = match into.get("type") {
                        None => allowed,
                        Some(Json::String(one)) => allowed
                            .into_iter()
                            .filter(|ty| ty.as_str() == Some(one))
                            .collect(),
                        Some(Json::Array(before)) => allowed
                            .into_iter()
                            .filter(|ty| before.contains(ty))
                            .collect(),
                        Some(_) => allowed,
                    };
                    let ty = match kept.len() {
                        0 => return Err(unsatisfiable("type")),
                        1 => kept.into_iter().next().unwrap(),
                        _ => Json::Array(kept),
                    };
                    into.insert("type".into(), ty);
                }
                "anyOf" | "oneOf" | "enum" | "const" | "x-nu" | "items" | "format"
                | "contentEncoding" => match into.get(keyword) {
                    None => {
                        into.insert(keyword.clone(), value.clone());
                    }
                    Some(before) if before == value => {}
                    Some(_) => return Err(unsatisfiable(keyword)),
                },
                // Not read: a description, a bound, what additional properties may be.
                _ => {}
            }
        }
        Ok(())
    }

    fn union(&mut self, members: &[Json], place: &Place) -> Result<String, Error> {
        let is_null = |member: &Json| member.get("type").and_then(Json::as_str) == Some("null");
        let nullable = members.iter().any(is_null);
        let place = place.or_null(nullable);
        // A value or null is one shape; several shapes are a union nothing reaches into.
        let place = if members.iter().filter(|member| !is_null(member)).count() > 1 {
            place.member()
        } else {
            place
        };
        let before = self.conversions.len();
        let mut types = Vec::new();
        for member in members {
            types.push(self.node(member, &place)?);
        }
        self.converted_in_union(&place, before)?;
        Ok(oneof(types))
    }

    /// A conversion inside a union of several shapes would run on every member.
    fn converted_in_union(&self, place: &Place, before: usize) -> Result<(), Error> {
        if place.in_union && self.conversions.len() > before {
            let what = self.conversions[before].ty.clone();
            return Err(Error::ConvertedInUnion {
                place: place.describe(),
                what,
            });
        }
        Ok(())
    }

    /// `x-nu`: a number counting units of a duration, a file size or a datetime.
    fn counted(&mut self, nu: &Json, ty: Option<&str>, place: &Place) -> Result<String, Error> {
        let counted = |why| Error::Counted {
            place: place.describe(),
            why,
        };
        let kind = nu
            .get("type")
            .and_then(Json::as_str)
            .ok_or_else(|| counted(CountedError::NoType))?;
        let unit = nu
            .get("unit")
            .and_then(Json::as_str)
            .ok_or_else(|| counted(CountedError::NoUnit))?;
        if !matches!(ty, Some("integer" | "number")) {
            return Err(counted(CountedError::NotANumber(
                ty.unwrap_or("untyped").to_string(),
            )));
        }
        let units = match kind {
            "duration" => UNITS_OF_DURATION,
            "datetime" => UNITS_OF_DATETIME,
            "filesize" => UNITS_OF_FILESIZE,
            other => return Err(counted(CountedError::UnknownKind(other.to_string()))),
        };
        if !units.contains(&unit) {
            return Err(counted(CountedError::UnknownUnit {
                kind: kind.to_string(),
                unit: unit.to_string(),
                units: units.iter().map(|unit| unit.to_string()).collect(),
            }));
        }
        self.convert(place, kind, Some(unit));
        Ok(kind.to_string())
    }

    fn object(
        &mut self,
        object: &serde_json::Map<String, Json>,
        place: &Place,
    ) -> Result<String, Error> {
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
            let filled = optional && field.reached();
            if filled {
                // Before anything under it, so the field is there when its own are filled;
                // and only where the record is one: a `null` on the way, the record itself
                // included, has no field to fill.
                self.fills.push(Fill {
                    path: field.path.clone(),
                    nullable: place.nullable.clone(),
                });
            }
            let ty = self.node(property, &field)?;
            if !optional {
                columns.push(format!("{}: {ty}", column(name)));
            } else if filled {
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
    ) -> Result<String, Error> {
        let Some(items) = object.get("items") else {
            return Ok("list<any>".to_string());
        };
        // A column of a table is a cell path, as a record's field is, where the table is
        // reached; the items of any other list are not.
        let rows = self.is_object(items);
        let item_place = if rows {
            place.field_less()
        } else {
            place.item()
        };
        let before = self.conversions.len();
        let ty = self.node(items, &item_place)?;
        if !item_place.reached() && self.conversions.len() > before {
            let what = self.conversions[before].ty.clone();
            return Err(Error::ConvertedInList {
                place: place.describe(),
                what,
            });
        }
        Ok(if rows {
            ty.replacen("record<", "table<", 1)
        } else {
            format!("list<{ty}>")
        })
    }

    /// Whether the schema describes an object, following a local `$ref` and the branches
    /// of an `allOf`.
    fn is_object(&self, schema: &Json) -> bool {
        self.is_object_within(schema, 0)
    }

    fn is_object_within(&self, schema: &Json, depth: usize) -> bool {
        if depth > 32 {
            return false;
        }
        if let Some(reference) = schema.get("$ref").and_then(Json::as_str) {
            return reference
                .strip_prefix('#')
                .and_then(|pointer| self.root.pointer(pointer))
                .is_some_and(|target| self.is_object_within(target, depth + 1));
        }
        schema.get("type").and_then(Json::as_str) == Some("object")
            || schema.get("properties").is_some()
            || schema
                .get("allOf")
                .and_then(Json::as_array)
                .is_some_and(|branches| {
                    branches
                        .iter()
                        .any(|branch| self.is_object_within(branch, depth + 1))
                })
    }

    fn convert(&mut self, place: &Place, ty: &str, unit: Option<&str>) {
        self.conversions.push(Conversion {
            path: place.path.clone(),
            ty: ty.to_string(),
            unit: unit.map(str::to_string),
            nullable: place.nullable.clone(),
        });
    }
}

impl Place {
    /// The rows of a table: the same cell paths, nothing between them and the top but what
    /// may be null on the way to the table.
    fn field_less(&self) -> Self {
        Place {
            path: self.path.clone(),
            in_list: self.in_list,
            in_union: self.in_union,
            nullable: self.nullable.clone(),
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
    if nu_utils::needs_quoting(name) {
        nu_utils::escape_quote_string(name)
    } else {
        name.to_string()
    }
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
        assert_eq!(shape.fills, vec![fill(&["name"], &[])]);
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
        assert_eq!(tabled.fills, vec![fill(&["rows", "note"], &[])]);
    }

    #[test]
    fn a_union_of_shapes_is_filled_for_none_of_them() {
        // A map of lists or a list, as `mise ls --json` writes with and without a tool: a
        // fill for the rows' optional column would add it to the map as a key.
        let schema = r##"{"$defs": {"version": {"type": "object", "required": ["version"],
            "properties": {"version": {"type": "string"}, "source": {"type": "string"}}}},
            "oneOf": [{"type": "object", "additionalProperties": {"type": "array", "items":
            {"$ref": "#/$defs/version"}}}, {"type": "array", "items": {"$ref": "#/$defs/version"}}]}"##;
        let shape = shape(schema).unwrap();
        assert_eq!(shape.ty.0, "oneof<record, table<version: string>>");
        assert!(shape.fills.is_empty(), "{:?}", shape.fills);
        // A conversion in there would run on the wrong shape too.
        let converted = r#"{"oneOf": [{"type": "string"}, {"type": "object", "required": ["at"],
            "properties": {"at": {"type": "string", "format": "date-time"}}}]}"#;
        assert!(super::shape(converted).is_err());
        // A shape or null is not such a union: the one shape is still filled, where it is
        // not the null.
        let nullable = r#"{"oneOf": [{"type": "null"}, {"type": "object", "required": ["id"],
            "properties": {"id": {"type": "integer"}, "note": {"type": "string"}}}]}"#;
        let shape = super::shape(nullable).unwrap();
        assert_eq!(
            shape.ty.0,
            "oneof<nothing, record<id: int, note: oneof<string, nothing>>>"
        );
        assert_eq!(shape.fills, vec![fill(&["note"], &[0])]);
    }

    #[test]
    fn a_fill_knows_what_may_be_null_on_the_way() {
        // `peer` may be left out or null, and `port` left out of it: the fill of `port`
        // is for the records that have a `peer`.
        let schema = r#"{"type": "object", "properties": {"peer": {"oneOf": [{"type": "null"},
            {"type": "object", "required": ["host"], "properties": {"host": {"type": "string"},
            "port": {"type": "integer"}}}]}}}"#;
        let shape = shape(schema).unwrap();
        assert_eq!(
            shape.ty.0,
            "record<peer: oneof<nothing, record<host: string, port: oneof<int, nothing>>>>"
        );
        // The record's own field first: `peer` is there when `port` is filled under it.
        assert_eq!(
            shape.fills,
            vec![fill(&["peer"], &[]), fill(&["peer", "port"], &[1])]
        );
    }

    fn fill(path: &[&str], nullable: &[usize]) -> Fill {
        Fill {
            path: path.iter().map(|part| part.to_string()).collect(),
            nullable: nullable.to_vec(),
        }
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
        let conversions: Vec<(String, String, Option<String>, Vec<usize>)> = shape
            .conversions
            .iter()
            .map(|c| {
                (
                    c.path.join("."),
                    c.ty.clone(),
                    c.unit.clone(),
                    c.nullable.clone(),
                )
            })
            .collect();
        assert_eq!(
            conversions,
            vec![
                ("took".into(), "duration".into(), Some("ms".into()), vec![]),
                ("at".into(), "datetime".into(), None, vec![]),
                ("size".into(), "filesize".into(), Some("kB".into()), vec![]),
                ("data".into(), "base64".into(), None, vec![]),
                (
                    "seen".into(),
                    "datetime".into(),
                    Some("sec".into()),
                    vec![1]
                ),
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
    fn all_of_is_read_as_what_its_branches_say_together() {
        // Inheritance as OpenAPI writes it: a pet is a new pet with an id.
        let schema = r##"{"$defs": {"NewPet": {"type": "object", "required": ["name"],
            "properties": {"name": {"type": "string"}, "tag": {"type": "string"},
            "born": {"type": "string", "format": "date-time"}}}},
            "allOf": [{"$ref": "#/$defs/NewPet"}, {"type": "object", "required": ["id"],
            "properties": {"id": {"type": "integer"}}}]}"##;
        let pet = shape(schema).unwrap();
        assert_eq!(
            pet.ty.0,
            "record<name: string, tag: oneof<string, nothing>, born: oneof<datetime, nothing>, id: int>"
        );
        assert_eq!(pet.fills, vec![fill(&["tag"], &[]), fill(&["born"], &[])]);
        assert_eq!(pet.conversions.len(), 1);
        assert_eq!(pet.conversions[0].path, ["born"]);
        // The rows of a table, and what the keywords beside `allOf` add.
        let rows = r##"{"$defs": {"NewPet": {"type": "object", "required": ["name"],
            "properties": {"name": {"type": "string"}, "tag": {"type": "string"},
            "born": {"type": "string", "format": "date-time"}}},
            "Pet": {"allOf": [{"$ref": "#/$defs/NewPet"}, {"type": "object", "required": ["id"],
            "properties": {"id": {"type": "integer"}}}]}},
            "type": "array", "items": {"allOf": [{"$ref": "#/$defs/Pet"}],
            "properties": {"sold": {"type": "boolean"}}}}"##;
        assert_eq!(
            ty(rows),
            "table<name: string, tag: oneof<string, nothing>, born: oneof<datetime, nothing>, id: int, sold: oneof<bool, nothing>>"
        );
        // A property several branches describe is what they say together: required by
        // one, typed by the other; nullable by one, not by the other.
        let together = r#"{"allOf": [{"type": "object", "properties": {"id": {"type": "integer"},
            "tag": {"type": ["string", "null"]}}}, {"required": ["id"], "properties":
            {"id": {"minimum": 1}, "tag": {"type": "string"}}}]}"#;
        assert_eq!(ty(together), "record<id: int, tag: oneof<string, nothing>>");
        // Branches that cannot all hold.
        for schema in [
            r#"{"allOf": [{"type": "string"}, {"type": "integer"}]}"#,
            r#"{"allOf": [{"type": "string", "format": "date-time"}, {"type": "string", "format": "email"}]}"#,
        ] {
            assert!(
                matches!(shape(schema), Err(Error::Unsatisfiable { .. })),
                "{schema}"
            );
        }
        // A branch naming itself adds nothing the second time round.
        let cyclic = r##"{"$defs": {"Node": {"allOf": [{"$ref": "#/$defs/Node"}, {"type": "object",
            "required": ["next"], "properties": {"next": {"$ref": "#/$defs/Node"}}}]}},
            "$ref": "#/$defs/Node"}"##;
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
