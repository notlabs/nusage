//! `nusage lsp`: Nushell's language server for the scripts nusage runs. It stands between an
//! editor and the `nu --lsp` it starts. A document whose shebang names nusage reaches Nushell
//! with its first line replaced by the line `nusage prelude` writes ([`crate::prelude`]),
//! which binds `$usage` with its type and defines the shadows of the scripts it calls, so
//! Nushell checks the script as nusage runs it. Every other line is the editor's own, so a
//! position there means the same on both sides. Line 0 is the editor's, and what Nushell
//! says about it is about the prelude: a request there is answered here, a result there is
//! dropped, or, for a definition, led to what the prelude stands for, a shadow to its script
//! and `$usage` to the header. What the header and the calls get wrong joins Nushell's
//! diagnostics. Any other document passes as it is.

use std::collections::HashMap;
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

use nusage_spec::Texts;
use serde_json::{Value as Json, json};

use crate::prelude::{self, Analysis};

/// Serve on standard input and output, with `nu --lsp` and `args` behind; the exit code is
/// Nushell's.
pub fn serve(args: &[String]) -> io::Result<i32> {
    let mut nu = Command::new("nu")
        .arg("--lsp")
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|err| io::Error::new(err.kind(), format!("cannot start `nu --lsp`: {err}")))?;
    let mut to_nu = nu.stdin.take().expect("piped");
    let from_nu = nu.stdout.take().expect("piped");
    let state = Arc::new(Mutex::new(State::default()));
    let editor = Arc::new(Mutex::new(io::stdout()));

    let answers = {
        let state = Arc::clone(&state);
        let editor = Arc::clone(&editor);
        std::thread::spawn(move || -> io::Result<()> {
            let mut from_nu = BufReader::new(from_nu);
            while let Some(message) = read_message(&mut from_nu)? {
                let message = state.lock().expect("state").nu_says(message);
                write_message(&mut *editor.lock().expect("editor"), &message)?;
            }
            Ok(())
        })
    };

    // Whether the editor said `exit`.
    let exited = (|| -> io::Result<bool> {
        let mut stdin = BufReader::new(io::stdin().lock());
        while let Some(message) = read_message(&mut stdin)? {
            // An editor may keep its end open until the server is gone.
            let exit = message.get("method").and_then(Json::as_str) == Some("exit");
            let routed = state.lock().expect("state").editor_says(message);
            for message in routed.to_editor {
                write_message(&mut *editor.lock().expect("editor"), &message)?;
            }
            if let Some(message) = routed.to_nu {
                write_message(&mut to_nu, &message)?;
            }
            if exit {
                return Ok(true);
            }
        }
        Ok(false)
    })();
    drop(to_nu);
    // Nushell's server waits for `exit` however its input ends, so one the editor left
    // without saying it is stopped here.
    if !matches!(exited, Ok(true)) {
        // One that is gone already is as good.
        nu.kill().ok();
    }
    let answered = answers.join().expect("the answering thread");
    let code = nu.wait()?.code().unwrap_or(1);
    exited?;
    answered?;
    Ok(code)
}

/// Where a message goes once it is read from the editor.
#[derive(Default)]
struct Routed {
    to_nu: Option<Json>,
    to_editor: Vec<Json>,
}

/// A document the editor has open.
struct Document {
    path: PathBuf,
    /// The editor's text.
    text: String,
    /// While its shebang names nusage, what Nushell sees in place of the first line.
    analysis: Option<Analysis>,
}

#[derive(Default)]
struct State {
    documents: HashMap<String, Document>,
    /// The editor's requests Nushell has yet to answer, by id: their method and document.
    pending: HashMap<String, (String, Option<String>)>,
    /// What Nushell last said of each document, as the editor is to see it.
    diagnostics: HashMap<String, Vec<Json>>,
    /// How a position counts characters on a line, as Nushell agreed with the editor.
    encoding: Encoding,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
enum Encoding {
    Utf8,
    #[default]
    Utf16,
    Utf32,
}

impl State {
    fn editor_says(&mut self, mut message: Json) -> Routed {
        let method = message
            .get("method")
            .and_then(Json::as_str)
            .map(str::to_string);
        let uri = message
            .pointer("/params/textDocument/uri")
            .and_then(Json::as_str)
            .map(str::to_string);
        let Some(method) = method else {
            // The editor answering Nushell.
            return Routed {
                to_nu: Some(message),
                to_editor: Vec::new(),
            };
        };
        if let Some(id) = message.get("id").cloned() {
            let on_line_0 = message
                .pointer("/params/position/line")
                .and_then(Json::as_u64)
                == Some(0);
            if on_line_0
                && uri
                    .as_deref()
                    .is_some_and(|uri| self.analysed(uri).is_some())
            {
                return Routed {
                    to_nu: None,
                    to_editor: vec![json!({"jsonrpc": "2.0", "id": id, "result": null})],
                };
            }
            self.pending.insert(id.to_string(), (method, uri));
            return Routed {
                to_nu: Some(message),
                to_editor: Vec::new(),
            };
        }
        let mut to_editor = Vec::new();
        match method.as_str() {
            "textDocument/didOpen" => {
                let opened = message.pointer("/params/textDocument").cloned();
                if let Some(opened) = opened
                    && let (Some(uri), Some(text)) = (
                        opened.get("uri").and_then(Json::as_str),
                        opened.get("text").and_then(Json::as_str),
                    )
                    && let Some(path) = path_of(uri)
                {
                    let analysis = prelude::analyze(&path, text, &self.texts(uri)).ok();
                    let document = Document {
                        path,
                        text: text.to_string(),
                        analysis,
                    };
                    let analysed = document.analysis.is_some();
                    if analysed {
                        message["params"]["textDocument"]["text"] = Json::String(document.seen());
                    }
                    self.documents.insert(uri.to_string(), document);
                    if analysed {
                        to_editor.push(self.publish(uri));
                    }
                }
            }
            "textDocument/didChange" => {
                if let Some(uri) = &uri
                    && let Some(changes) = message
                        .pointer("/params/contentChanges")
                        .and_then(Json::as_array)
                        .cloned()
                {
                    let texts = self.texts(uri);
                    let encoding = self.encoding;
                    if let Some(document) = self.documents.get_mut(uri) {
                        for change in &changes {
                            document.apply(change, encoding);
                        }
                        // A shebang typed or taken away changes what Nushell is to see, so it
                        // gets the whole text then, as it does while there is a prelude; the
                        // editor's own changes do otherwise.
                        let was = document.analysis.is_some();
                        document.analysis =
                            prelude::analyze(&document.path, &document.text, &texts).ok();
                        if was || document.analysis.is_some() {
                            message["params"]["contentChanges"] =
                                json!([{"text": document.seen()}]);
                            if document.analysis.is_none() {
                                self.diagnostics.remove(uri);
                            }
                            to_editor.push(self.publish(uri));
                        }
                    }
                }
            }
            "textDocument/didClose" => {
                if let Some(uri) = &uri
                    && let Some(document) = self.documents.remove(uri)
                    && document.analysis.is_some()
                {
                    self.diagnostics.remove(uri);
                    to_editor.push(json!({
                        "jsonrpc": "2.0",
                        "method": "textDocument/publishDiagnostics",
                        "params": {"uri": uri, "diagnostics": []},
                    }));
                }
            }
            _ => {}
        }
        Routed {
            to_nu: Some(message),
            to_editor,
        }
    }

    fn nu_says(&mut self, mut message: Json) -> Json {
        if message.get("method").and_then(Json::as_str) == Some("textDocument/publishDiagnostics") {
            let uri = message
                .pointer("/params/uri")
                .and_then(Json::as_str)
                .map(str::to_string);
            if let Some(uri) = uri
                && let Some((document, _)) = self.analysed(&uri)
            {
                let first = document.line_0_range(self.encoding);
                let said = message
                    .pointer("/params/diagnostics")
                    .and_then(Json::as_array)
                    .cloned()
                    .unwrap_or_default()
                    .into_iter()
                    .map(|mut diagnostic| {
                        if line_of(&diagnostic["range"]) == Some(0) {
                            // About the prelude: a mistake of nusage's, shown where it stands.
                            let text = diagnostic["message"].as_str().unwrap_or("").to_string();
                            diagnostic["message"] = Json::String(format!(
                                "in the line nusage puts here for Nushell: {text}"
                            ));
                            diagnostic["range"] = first.clone();
                        }
                        diagnostic
                    })
                    .collect();
                self.diagnostics.insert(uri.clone(), said);
                return self.publish(&uri);
            }
            return message;
        }
        let Some(id) = message.get("id") else {
            return message;
        };
        if message.get("method").is_some() {
            // Nushell asking the editor.
            return message;
        }
        let Some((method, uri)) = self.pending.remove(&id.to_string()) else {
            return message;
        };
        if method == "initialize" {
            self.encoding = match message
                .pointer("/result/capabilities/positionEncoding")
                .and_then(Json::as_str)
            {
                Some("utf-8") => Encoding::Utf8,
                Some("utf-32") => Encoding::Utf32,
                _ => Encoding::Utf16,
            };
            return message;
        }
        if let Some(result) = message.get_mut("result") {
            self.revise(&method, uri.as_deref(), result);
        }
        message
    }

    /// Nushell's answer to a request, with what it says of the prelude dropped or led to what
    /// the prelude stands for.
    fn revise(&self, method: &str, uri: Option<&str>, result: &mut Json) {
        let analysed = uri.is_some_and(|uri| self.analysed(uri).is_some());
        match method {
            "textDocument/definition"
            | "textDocument/declaration"
            | "textDocument/typeDefinition"
            | "textDocument/implementation" => {
                let found: Vec<Json> = match result.take() {
                    Json::Null => Vec::new(),
                    Json::Array(items) => items,
                    one => vec![one],
                };
                *result = Json::Array(
                    found
                        .into_iter()
                        .filter_map(|location| self.lead(location))
                        .collect(),
                );
            }
            "textDocument/references" | "workspace/symbol" => {
                if let Some(items) = result.as_array_mut() {
                    items.retain(|item| {
                        let location = item.get("location").unwrap_or(item);
                        !self.on_line_0(location.get("uri"), location.get("range"))
                    });
                }
            }
            "textDocument/documentHighlight" | "textDocument/documentSymbol" => {
                if analysed && let Some(items) = result.as_array_mut() {
                    drop_line_0(items);
                }
            }
            "textDocument/inlayHint" => {
                if analysed && let Some(hints) = result.as_array_mut() {
                    hints.retain(|hint| {
                        hint.pointer("/position/line").and_then(Json::as_u64) != Some(0)
                    });
                }
            }
            "textDocument/semanticTokens/full" => {
                if analysed && let Some(data) = result.get_mut("data") {
                    *data = Json::from(tokens_after_line_0(data));
                }
            }
            "textDocument/rename" => {
                if let Some(changes) = result.get_mut("changes").and_then(Json::as_object_mut) {
                    for (uri, edits) in changes.iter_mut() {
                        if self.analysed(uri).is_some()
                            && let Some(edits) = edits.as_array_mut()
                        {
                            edits.retain(|edit| line_of(&edit["range"]) != Some(0));
                        }
                    }
                }
                if let Some(edits) = result
                    .get_mut("documentChanges")
                    .and_then(Json::as_array_mut)
                {
                    for edit in edits {
                        let uri = edit.pointer("/textDocument/uri").and_then(Json::as_str);
                        if uri.is_some_and(|uri| self.analysed(uri).is_some())
                            && let Some(edits) = edit.get_mut("edits").and_then(Json::as_array_mut)
                        {
                            edits.retain(|edit| line_of(&edit["range"]) != Some(0));
                        }
                    }
                }
            }
            "textDocument/prepareRename" => {
                let range = result.get("range").unwrap_or(result);
                if analysed && line_of(range) == Some(0) {
                    *result = Json::Null;
                }
            }
            _ => {}
        }
    }

    /// A location as the editor is to see it: one in a prelude led to what it stands for, a
    /// shadow to its script and `$usage` to the header, or none.
    fn lead(&self, mut location: Json) -> Option<Json> {
        let link = location.get("targetUri").is_some();
        let (uri_key, range_key) = if link {
            ("targetUri", "targetSelectionRange")
        } else {
            ("uri", "range")
        };
        let uri = location.get(uri_key)?.as_str()?.to_string();
        let Some((document, analysis)) = self.analysed(&uri) else {
            return Some(location);
        };
        if line_of(&location[range_key]) != Some(0) {
            return Some(location);
        }
        let character = location[range_key]
            .pointer("/start/character")
            .and_then(Json::as_u64)? as usize;
        let at = byte_at(&analysis.line, character, self.encoding);
        let shadow = analysis.shadows.iter().find(|(span, _)| span.contains(&at));
        let (target, range) = match shadow {
            Some((_, script)) => (file_uri(script), zero_range()),
            // Before the shadows is `$usage`, which the header declares.
            None if analysis
                .shadows
                .first()
                .is_none_or(|(span, _)| at < span.start) =>
            {
                let line = document.header_line()?;
                let width = units(document.line(line), self.encoding);
                (
                    uri.clone(),
                    json!({"start": {"line": line, "character": 0}, "end": {"line": line, "character": width}}),
                )
            }
            None => return None,
        };
        location[uri_key] = Json::String(target);
        location[range_key] = range.clone();
        if link {
            location["targetRange"] = range;
        }
        Some(location)
    }

    fn on_line_0(&self, uri: Option<&Json>, range: Option<&Json>) -> bool {
        uri.and_then(Json::as_str)
            .is_some_and(|uri| self.analysed(uri).is_some())
            && range.is_some_and(|range| line_of(range) == Some(0))
    }

    /// The document and its analysis, while Nushell sees it with a prelude.
    fn analysed(&self, uri: &str) -> Option<(&Document, &Analysis)> {
        let document = self.documents.get(uri)?;
        Some((document, document.analysis.as_ref()?))
    }

    /// The editor's other open documents, as they are and not as saved, for what this one
    /// reads of them.
    fn texts(&self, except: &str) -> Texts {
        self.documents
            .iter()
            .filter(|(uri, _)| uri.as_str() != except)
            .map(|(_, document)| (document.path.clone(), document.text.clone()))
            .collect()
    }

    /// The diagnostics of a document: Nushell's last, and, while it has a prelude, what the
    /// header and the calls get wrong.
    fn publish(&self, uri: &str) -> Json {
        let mut diagnostics = self.diagnostics.get(uri).cloned().unwrap_or_default();
        if let Some((document, analysis)) = self.analysed(uri) {
            diagnostics.extend(document.findings(analysis, self.encoding));
        }
        json!({
            "jsonrpc": "2.0",
            "method": "textDocument/publishDiagnostics",
            "params": {"uri": uri, "diagnostics": diagnostics},
        })
    }
}

impl Document {
    /// The text Nushell sees: the prelude in place of the first line, while there is one.
    fn seen(&self) -> String {
        let Some(analysis) = &self.analysis else {
            return self.text.clone();
        };
        match self.text.split_once('\n') {
            Some((_, rest)) => format!("{}\n{rest}", analysis.line),
            None => analysis.line.clone(),
        }
    }

    fn line(&self, index: usize) -> &str {
        self.text.split('\n').nth(index).unwrap_or("")
    }

    /// The first line's range, the editor's.
    fn line_0_range(&self, encoding: Encoding) -> Json {
        let width = units(self.line(0), encoding);
        json!({"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": width}})
    }

    /// The line of the header's first node, from 0.
    fn header_line(&self) -> Option<usize> {
        self.text.split('\n').position(|line| {
            ["#USAGE", "#[USAGE]", "# [USAGE]"]
                .iter()
                .any(|prefix| line.starts_with(prefix))
        })
    }

    fn findings(&self, analysis: &Analysis, encoding: Encoding) -> Vec<Json> {
        let mut found = Vec::new();
        if let Some(header) = &analysis.header {
            let line = header.line.map_or(0, |line| line.saturating_sub(1));
            let width = units(self.line(line), encoding);
            found.push(json!({
                "range": {"start": {"line": line, "character": 0}, "end": {"line": line, "character": width}},
                "severity": 1,
                "source": "nusage",
                "message": header.message,
            }));
        }
        for finding in &analysis.calls.findings {
            found.push(json!({
                "range": {
                    "start": self.position(finding.span.start, encoding),
                    "end": self.position(finding.span.end, encoding),
                },
                "severity": 1,
                "source": "nusage",
                "message": finding.message,
            }));
        }
        found
    }

    /// A byte offset of the editor's text as a position.
    fn position(&self, offset: usize, encoding: Encoding) -> Json {
        let before = &self.text[..offset.min(self.text.len())];
        let line = before.matches('\n').count();
        let start = before.rfind('\n').map_or(0, |at| at + 1);
        json!({"line": line, "character": units(&before[start..], encoding)})
    }

    /// Apply one of the editor's changes: a range and its new text, or the whole text.
    fn apply(&mut self, change: &Json, encoding: Encoding) {
        let Some(text) = change.get("text").and_then(Json::as_str) else {
            return;
        };
        let Some(range) = change.get("range") else {
            self.text = text.to_string();
            return;
        };
        let offset = |key: &str| -> Option<usize> {
            let line = range.pointer(&format!("/{key}/line"))?.as_u64()? as usize;
            let character = range.pointer(&format!("/{key}/character"))?.as_u64()? as usize;
            let start = self
                .text
                .split_inclusive('\n')
                .take(line)
                .map(str::len)
                .sum::<usize>();
            let rest = &self.text[start.min(self.text.len())..];
            let rest = rest.split('\n').next().unwrap_or("");
            Some(start + byte_at(rest, character, encoding))
        };
        if let (Some(start), Some(end)) = (offset("start"), offset("end"))
            && start <= end
            && end <= self.text.len()
        {
            self.text.replace_range(start..end, text);
        }
    }
}

/// How many of the encoding's units a line's text counts.
fn units(text: &str, encoding: Encoding) -> usize {
    match encoding {
        Encoding::Utf8 => text.len(),
        Encoding::Utf16 => text.encode_utf16().count(),
        Encoding::Utf32 => text.chars().count(),
    }
}

/// The byte offset in a line's text that a position's character, in the encoding's units,
/// stands for; past the end is the end.
fn byte_at(text: &str, character: usize, encoding: Encoding) -> usize {
    let mut counted = 0;
    for (at, c) in text.char_indices() {
        if counted >= character {
            return at;
        }
        counted += match encoding {
            Encoding::Utf8 => c.len_utf8(),
            Encoding::Utf16 => c.len_utf16(),
            Encoding::Utf32 => 1,
        };
    }
    text.len()
}

fn line_of(range: &Json) -> Option<u64> {
    range.pointer("/start/line").and_then(Json::as_u64)
}

fn zero_range() -> Json {
    json!({"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}})
}

/// Highlights or symbols, without those on line 0, a symbol's children included.
fn drop_line_0(items: &mut Vec<Json>) {
    items.retain(|item| {
        let range = item
            .get("range")
            .or_else(|| item.pointer("/location/range"));
        range.and_then(line_of) != Some(0)
    });
    for item in items {
        if let Some(children) = item.get_mut("children").and_then(Json::as_array_mut) {
            drop_line_0(children);
        }
    }
}

/// Semantic tokens without those on line 0. Each token is five numbers, its line and start
/// counted from the token before it, so the first one kept counts its line afresh.
fn tokens_after_line_0(data: &Json) -> Vec<u64> {
    let numbers: Vec<u64> = data
        .as_array()
        .map(|items| items.iter().filter_map(Json::as_u64).collect())
        .unwrap_or_default();
    let mut out = Vec::with_capacity(numbers.len());
    let mut line = 0;
    let mut kept_line = 0;
    let mut kept_start = 0;
    let mut start = 0;
    for token in numbers.as_chunks::<5>().0 {
        if token[0] > 0 {
            line += token[0];
            start = token[1];
        } else {
            start += token[1];
        }
        if line == 0 {
            continue;
        }
        let delta_line = line - kept_line;
        let delta_start = if delta_line == 0 {
            start - kept_start
        } else {
            start
        };
        out.extend([delta_line, delta_start, token[2], token[3], token[4]]);
        kept_line = line;
        kept_start = start;
    }
    out
}

/// The path a `file:` URI names, its escapes decoded.
fn path_of(uri: &str) -> Option<PathBuf> {
    let rest = uri.strip_prefix("file://")?;
    let bytes = rest.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at] == b'%'
            && let Some(byte) = rest
                .get(at + 1..at + 3)
                .and_then(|hex| u8::from_str_radix(hex, 16).ok())
        {
            decoded.push(byte);
            at += 3;
            continue;
        }
        decoded.push(bytes[at]);
        at += 1;
    }
    let path = String::from_utf8(decoded).ok()?;
    // `file:///C:/x.nu` names `C:/x.nu`.
    let path = match path.strip_prefix('/') {
        Some(rest) if cfg!(windows) && rest.get(1..2) == Some(":") => rest.to_string(),
        _ => path,
    };
    Some(PathBuf::from(path))
}

/// The `file:` URI of a path, with what a URI cannot hold escaped.
fn file_uri(path: &Path) -> String {
    let text = path.to_string_lossy().replace('\\', "/");
    let mut uri = String::from("file://");
    if !text.starts_with('/') {
        uri.push('/');
    }
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || b"/-._~:".contains(&byte) {
            uri.push(byte as char);
        } else {
            uri.push_str(&format!("%{byte:02X}"));
        }
    }
    uri
}

/// One message of the base protocol: headers, a blank line, and as many bytes of JSON as
/// `Content-Length` says. `None` at the end of the stream.
fn read_message(reader: &mut impl BufRead) -> io::Result<Option<Json>> {
    let mut length = None;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            return Ok(None);
        }
        let line = line.trim_end();
        if line.is_empty() {
            if length.is_some() {
                break;
            }
            continue;
        }
        if let Some((name, value)) = line.split_once(':')
            && name.eq_ignore_ascii_case("content-length")
        {
            length = value.trim().parse::<usize>().ok();
        }
    }
    let mut body = vec![0; length.unwrap_or(0)];
    // A stream may end partway through a message: `nu` that is told to exit can go before
    // its answer to `shutdown` is all written. That is the stream's end too.
    match reader.read_exact(&mut body) {
        Err(err) if err.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
        read => read?,
    }
    serde_json::from_slice(&body)
        .map(Some)
        .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))
}

fn write_message(writer: &mut impl Write, message: &Json) -> io::Result<()> {
    let body = serde_json::to_vec(message)?;
    write!(writer, "Content-Length: {}\r\n\r\n", body.len())?;
    writer.write_all(&body)?;
    writer.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn positions_count_the_agreed_units() {
        let text = "aé😀b";
        assert_eq!(units(text, Encoding::Utf8), 8);
        assert_eq!(units(text, Encoding::Utf16), 5);
        assert_eq!(units(text, Encoding::Utf32), 4);
        assert_eq!(byte_at(text, 4, Encoding::Utf16), 7);
        assert_eq!(byte_at(text, 3, Encoding::Utf32), 7);
        assert_eq!(byte_at(text, 99, Encoding::Utf16), text.len());
    }

    #[test]
    fn tokens_on_line_0_are_dropped_and_the_rest_recounted() {
        // Two tokens on line 0, at 2 and 7, then two on line 2, at 4 and 7.
        let data = json!([0, 2, 3, 0, 0, 0, 5, 1, 0, 0, 2, 4, 2, 0, 0, 0, 3, 1, 0, 0]);
        assert_eq!(tokens_after_line_0(&data), [2, 4, 2, 0, 0, 0, 3, 1, 0, 0]);
    }

    #[test]
    fn an_edit_lands_where_the_editor_says() {
        let mut document = Document {
            path: PathBuf::from("/x.nu"),
            text: "#!/usr/bin/env nusage\nlet é = 1\nprint $é\n".into(),
            analysis: None,
        };
        document.apply(
            &json!({"range": {"start": {"line": 2, "character": 7}, "end": {"line": 2, "character": 8}}, "text": "e"}),
            Encoding::Utf16,
        );
        assert_eq!(
            document.text,
            "#!/usr/bin/env nusage\nlet é = 1\nprint $e\n"
        );
        document.apply(&json!({"text": "whole"}), Encoding::Utf16);
        assert_eq!(document.text, "whole");
    }

    #[test]
    fn uris_and_paths() {
        let path = PathBuf::from("/a b/ç.nu");
        assert_eq!(file_uri(&path), "file:///a%20b/%C3%A7.nu");
        assert_eq!(path_of(&file_uri(&path)), Some(path));
    }

    #[test]
    fn a_stream_that_ends_partway_through_a_message_has_ended() {
        let whole = "Content-Length: 2\r\n\r\n{}";
        let mut stream = io::Cursor::new(format!("{whole}Content-Length: 40\r\n\r\n{{\"id\""));
        assert_eq!(read_message(&mut stream).unwrap(), Some(json!({})));
        assert_eq!(read_message(&mut stream).unwrap(), None);
    }
}
