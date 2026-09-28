///|
/// Text format parser for change window plans.
///
/// One record per line, fields separated by `;`, each field written as
/// `key=value`:
///
/// ```text
/// id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:30;risk=high;depends=
/// id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database
/// ```
///
/// Blank lines and lines starting with `#` are ignored. Empty fields such as
/// the trailing `;` above and the empty `depends=` value are ignored as well.

///|
/// Parse a plan from its text form.
///
/// A record that produces an error is dropped from `plan.windows`; a record
/// that only produces warnings is kept. Every problem is reported in
/// `plan.diagnostics` with the 1-based line number it came from.
pub fn parse_plan(source : String) -> Plan {
  let windows : Array[Window] = []
  let diagnostics : Array[Diagnostic] = []
  let normalized = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let mut line_number = 0
  for raw in normalized.split("\n") {
    line_number = line_number + 1
    let line = raw.to_owned()
    let trimmed = line.trim()
    if trimmed.length() == 0 {
      continue
    }
    if trimmed[0] == '#' {
      continue
    }
    let mut id = ""
    let mut service = ""
    let mut start_text = ""
    let mut end_text = ""
    let mut risk_text = ""
    let mut depends_text = ""
    let mut kind_text = ""
    let mut has_id = false
    let mut has_start = false
    let mut has_end = false
    let seen : Array[String] = []
    let mut record_ok = true
    for field in line.split(";") {
      let piece = field.trim()
      if piece.length() == 0 {
        continue
      }
      let parsed = match split_field(piece) {
        Some(value) => value
        None => {
          diagnostics.push(
            error_at(line_number, "malformed-field", piece.to_owned()),
          )
          record_ok = false
          continue
        }
      }
      let key = parsed.0
      let value = parsed.1
      if !is_known_key(key) {
        diagnostics.push(warning_at(line_number, "unknown-field", key))
        continue
      }
      if seen.contains(key) {
        diagnostics.push(error_at(line_number, "duplicate-field", key))
        record_ok = false
        continue
      }
      seen.push(key)
      if key == "id" {
        id = value
        has_id = true
      } else if key == "service" {
        service = value
      } else if key == "start" {
        start_text = value
        has_start = true
      } else if key == "end" {
        end_text = value
        has_end = true
      } else if key == "risk" {
        risk_text = value
      } else if key == "kind" {
        kind_text = value
      } else {
        depends_text = value
      }
    }
    if !has_id {
      diagnostics.push(error_at(line_number, "missing-field", "id"))
      record_ok = false
    }
    if !has_start {
      diagnostics.push(error_at(line_number, "missing-field", "start"))
      record_ok = false
    }
    if !has_end {
      diagnostics.push(error_at(line_number, "missing-field", "end"))
      record_ok = false
    }
    let mut start_minutes = 0
    let mut end_minutes = 0
    if has_start {
      match parse_instant(start_text) {
        Some(value) => start_minutes = value
        None => {
          diagnostics.push(
            error_at(
              line_number,
              "invalid-instant",
              "start=\"" + start_text + "\"",
            ),
          )
          record_ok = false
        }
      }
    }
    if has_end {
      match parse_instant(end_text) {
        Some(value) => end_minutes = value
        None => {
          diagnostics.push(
            error_at(line_number, "invalid-instant", "end=\"" + end_text + "\""),
          )
          record_ok = false
        }
      }
    }
    if record_ok && end_minutes <= start_minutes {
      diagnostics.push(
        error_at(
          line_number,
          "end-not-after-start",
          format_instant(start_minutes) + " -> " + format_instant(end_minutes),
        ),
      )
      record_ok = false
    }
    let mut risk = Risk::Medium
    if risk_text != "" {
      match Risk::parse(risk_text) {
        Some(value) => risk = value
        None => {
          diagnostics.push(error_at(line_number, "invalid-risk", risk_text))
          record_ok = false
        }
      }
    }
    let depends : Array[String] = []
    if depends_text != "" {
      for raw_dependency in depends_text.split(",") {
        let dependency = raw_dependency.to_owned().trim().to_owned()
        if dependency == "" {
          continue
        }
        if !is_valid_identifier(dependency) {
          diagnostics.push(
            error_at(line_number, "invalid-dependency", dependency),
          )
          record_ok = false
          continue
        }
        if depends.contains(dependency) {
          diagnostics.push(
            warning_at(line_number, "duplicate-dependency", dependency),
          )
          continue
        }
        depends.push(dependency)
      }
    }
    let mut kind = WindowKind::Change
    if kind_text != "" {
      match WindowKind::parse(kind_text) {
        Some(value) => kind = value
        None => {
          diagnostics.push(error_at(line_number, "invalid-kind", kind_text))
          record_ok = false
        }
      }
    }
    if kind == WindowKind::Freeze {
      if risk_text != "" {
        diagnostics.push(
          warning_at(line_number, "ignored-field-on-freeze", "risk"),
        )
      }
      if depends.length() > 0 {
        diagnostics.push(
          error_at(line_number, "freeze-with-dependency", join(depends, ",")),
        )
        record_ok = false
      }
    }
    if !record_ok {
      continue
    }
    if !is_valid_identifier(id) {
      diagnostics.push(error_at(line_number, "invalid-id", id))
      continue
    }
    match find_window(windows, id) {
      Some(_) => diagnostics.push(error_at(line_number, "duplicate-id", id))
      None => ()
    }
    windows.push({
      id,
      service,
      start: start_minutes,
      end: end_minutes,
      risk,
      depends,
      kind,
    })
  }
  { windows, diagnostics, }
}

///|
/// Field names accepted inside a record.
fn is_known_key(key : String) -> Bool {
  key == "id" ||
  key == "service" ||
  key == "start" ||
  key == "end" ||
  key == "risk" ||
  key == "kind" ||
  key == "depends"
}

///|
/// Diagnostic with error severity.
fn error_at(line : Int, code : String, detail : String) -> Diagnostic {
  { severity: Severity::Error, code, line, detail, }
}

///|
/// Diagnostic with warning severity.
fn warning_at(line : Int, code : String, detail : String) -> Diagnostic {
  { severity: Severity::Warning, code, line, detail, }
}
