//! A Nushell dialect of JSON Schema.
//!
//! JSON carries less than Nushell does: a duration, a file size or a datetime arrives as a
//! number or as text. The dialect is draft 2020-12 with one vocabulary, `x-nu`, which says
//! what a number counts, `{"type": "duration", "unit": "ms"}`, so a reader knows the value
//! as Nushell does. [`shape`] reads a schema in this dialect as a Nushell type, with the
//! fields to fill where a document leaves an optional property out, and the conversions to
//! run after decoding; that is what a wrapper around a command or an API needs to return a
//! value of the declared type. [`dialect`] holds the meta-schemas, and with the `validate`
//! feature [`validate`] holds documents to a schema and a schema to the dialect.
//!
//! The mapping from a schema to a type is the obvious one: an object is a `record` of its
//! properties in their order, an array of objects a `table`, any other array a `list`,
//! `integer` is `int`, `number` is `float`, and a property the schema does not require is
//! `oneof<T, nothing>`, filled with `null` when absent so it is there to read. A string with
//! `format: date-time` becomes a datetime, one with `contentEncoding: base64` becomes
//! binary, and a number with `x-nu` becomes what it counts. `anyOf`, `oneOf` and a list of
//! types are `oneof<…>`; `enum` and `const` take the type of their values; a local `$ref` is
//! followed. What the reader does not read is `any`: `allOf`, `not`, conditionals,
//! `patternProperties`.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod dialect;
mod shape;
#[cfg(feature = "validate")]
pub mod validate;

pub use shape::{
    Conversion, CountedError, Error, Fill, NuType, Shape, UNITS_OF_DATETIME, UNITS_OF_DURATION,
    UNITS_OF_FILESIZE, shape, shape_of,
};
