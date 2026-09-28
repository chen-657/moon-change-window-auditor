///|
/// Machine readable rendering of plans, audits and safe slots as JSON.
///
/// The emitter is a small purpose built writer instead of a generic
/// serialisation library, because the package must stay dependency free and the
/// output has to be byte for byte reproducible on every backend.
///
/// Layout rules, applied everywhere:
///
/// - two spaces of indentation per nesting level,
/// - one field or element per line, with a comma between siblings and none
///   after the last one,
/// - an empty array renders inline as `[]`,
/// - every document ends with exactly one newline.
///
/// Every builder takes the indentation depth of the value it produces, so a
/// nested object closes at the depth it opened at and a comma between siblings
/// can never be forgotten.

///|
/// Lower case hexadecimal digit of a value in `0-15`.
fn hex_digit(value : Int) -> String {
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  digits[value]
}

///|
/// Escape one character for the body of a JSON string.
fn escape_char(character : Char) -> String {
  match character {
    '"' => "\\\""
    '\\' => "\\\\"
    '\n' => "\\n"
    '\r' => "\\r"
    '\t' => "\\t"
    // 0x08 backspace
    '\u{0008}' => "\\b"
    // 0x0c form feed
    '\u{000C}' => "\\f"
    _ =>
      if character.to_int() < 0x20 {
        let code = character.to_int()
        let builder = StringBuilder()
        builder.write_string("\\u00")
        builder.write_string(hex_digit(code / 16))
        builder.write_string(hex_digit(code % 16))
        builder.to_string()
      } else {
        character.to_string()
      }
  }
}

///|
/// Escape a string for the body of a JSON string.
///
/// `"` becomes `\"`, `\` becomes `\\`, a newline `\n`, a carriage return `\r`, a
/// tab `\t`, a backspace `\b` and a form feed `\f`. Any other character below
/// `0x20` becomes `\u00XX` with two lower case hexadecimal digits. Everything
/// from `0x20` upwards passes through unchanged, so UTF-8 text such as `订单`
/// stays readable and is not turned into `\u` escapes.
pub fn json_escape(text : String) -> String {
  let builder = StringBuilder()
  for character in text {
    builder.write_string(escape_char(character))
  }
  builder.to_string()
}

///|
/// The indentation of one nesting level, as a string.
fn indent_text(depth : Int) -> String {
  let builder = StringBuilder()
  for index = 0; index < depth; index = index + 1 {
    builder.write_string("  ")
  }
  builder.to_string()
}

///|
/// A JSON string literal, with the body escaped.
fn json_text(value : String) -> String {
  "\"" + json_escape(value) + "\""
}

///|
/// One `"key": value` line at the given depth.
fn json_field(depth : Int, key : String, value : String) -> String {
  indent_text(depth) + json_text(key) + ": " + value
}

///|
/// An object from already rendered field lines.
///
/// `depth` is the depth of the braces; the field lines carry their own
/// indentation and are expected to sit one level deeper. An empty field list
/// renders inline as `{}`.
fn json_object(depth : Int, fields : Array[String]) -> String {
  if fields.length() == 0 {
    return "{}"
  }
  let builder = StringBuilder()
  builder.write_string("{\n")
  for index = 0; index < fields.length(); index = index + 1 {
    builder.write_string(fields[index])
    if index + 1 < fields.length() {
      builder.write_char(',')
    }
    builder.write_char('\n')
  }
  builder.write_string(indent_text(depth))
  builder.write_char('}')
  builder.to_string()
}

///|
/// An array from already rendered elements.
///
/// `depth` is the depth of the brackets; every element is placed on its own line
/// one level deeper. An empty array renders inline as `[]`.
fn json_array(depth : Int, elements : Array[String]) -> String {
  if elements.length() == 0 {
    return "[]"
  }
  let builder = StringBuilder()
  builder.write_string("[\n")
  for index = 0; index < elements.length(); index = index + 1 {
    builder.write_string(indent_text(depth + 1))
    builder.write_string(elements[index])
    if index + 1 < elements.length() {
      builder.write_char(',')
    }
    builder.write_char('\n')
  }
  builder.write_string(indent_text(depth))
  builder.write_char(']')
  builder.to_string()
}

///|
/// An array of strings, one per line.
fn json_text_array(depth : Int, values : Array[String]) -> String {
  let elements : Array[String] = []
  for value in values {
    elements.push(json_text(value))
  }
  json_array(depth, elements)
}

///|
/// One window object.
///
/// The field order is `id`, `service`, `kind`, `start`, `end`, `minutes`,
/// `risk`, `depends`. `start` and `end` are rendered with `format_instant`,
/// `minutes` is the raw length in minutes, `kind` and `risk` use their lower
/// case `label()` and `depends` keeps the input order of the dependencies. A
/// freeze carries no dependencies of its own, so its `depends` array is empty.
fn json_window_object(depth : Int, window : Window) -> String {
  json_object(depth, [
    json_field(depth + 1, "id", json_text(window.id)),
    json_field(depth + 1, "service", json_text(window.service)),
    json_field(depth + 1, "kind", json_text(window.kind.label())),
    json_field(depth + 1, "start", json_text(format_instant(window.start))),
    json_field(depth + 1, "end", json_text(format_instant(window.end))),
    json_field(depth + 1, "minutes", window.duration().to_string()),
    json_field(depth + 1, "risk", json_text(window.risk.label())),
    json_field(depth + 1, "depends", json_text_array(depth + 1, window.depends)),
  ])
}

///|
/// One diagnostic object.
fn json_diagnostic_object(depth : Int, diagnostic : Diagnostic) -> String {
  json_object(depth, [
    json_field(depth + 1, "severity", json_text(diagnostic.severity.label())),
    json_field(depth + 1, "line", diagnostic.line.to_string()),
    json_field(depth + 1, "code", json_text(diagnostic.code)),
    json_field(depth + 1, "detail", json_text(diagnostic.detail)),
  ])
}

///|
/// One overlap object.
fn json_overlap_object(depth : Int, overlap : Overlap) -> String {
  json_object(depth, [
    json_field(depth + 1, "first", json_text(overlap.first)),
    json_field(depth + 1, "second", json_text(overlap.second)),
    json_field(depth + 1, "minutes", overlap.minutes.to_string()),
    json_field(depth + 1, "impact", json_text(overlap.impact.label())),
  ])
}

///|
/// One freeze conflict object.
fn json_conflict_object(depth : Int, conflict : FreezeConflict) -> String {
  json_object(depth, [
    json_field(depth + 1, "window", json_text(conflict.window_id)),
    json_field(depth + 1, "freeze", json_text(conflict.freeze_id)),
    json_field(depth + 1, "minutes", conflict.minutes.to_string()),
  ])
}

///|
/// One dependency issue object.
fn json_issue_object(depth : Int, issue : DependencyIssue) -> String {
  json_object(depth, [
    json_field(depth + 1, "window", json_text(issue.window_id)),
    json_field(depth + 1, "dependency", json_text(issue.dependency)),
    json_field(depth + 1, "problem", json_text(issue.problem.label())),
    json_field(depth + 1, "severity", json_text(issue.severity.label())),
    json_field(depth + 1, "detail", json_text(issue.detail)),
  ])
}

///|
/// One safe slot object.
fn json_slot_object(depth : Int, slot : Slot) -> String {
  json_object(depth, [
    json_field(depth + 1, "start", json_text(format_instant(slot.start))),
    json_field(depth + 1, "end", json_text(format_instant(slot.end))),
    json_field(depth + 1, "minutes", slot.duration().to_string()),
  ])
}

///|
/// An array of window objects at the given depth.
fn json_window_array(depth : Int, windows : Array[Window]) -> String {
  let elements : Array[String] = []
  for window in windows {
    elements.push(json_window_object(depth + 1, window))
  }
  json_array(depth, elements)
}

///|
/// An array of diagnostic objects at the given depth.
fn json_diagnostic_array(
  depth : Int,
  diagnostics : Array[Diagnostic],
) -> String {
  let elements : Array[String] = []
  for diagnostic in diagnostics {
    elements.push(json_diagnostic_object(depth + 1, diagnostic))
  }
  json_array(depth, elements)
}

///|
/// Render a plan as JSON: an object with `windows` and `diagnostics`.
///
/// Windows appear in `sort_windows_by_start` order, which is stable for equal
/// start minutes, so the same plan always renders the same bytes. Diagnostics
/// keep their input order, because their line numbers are only meaningful in
/// that order.
pub fn render_plan_json(plan : Plan) -> String {
  json_object(0, [
    json_field(
      1,
      "windows",
      json_window_array(1, sort_windows_by_start(plan.windows)),
    ),
    json_field(1, "diagnostics", json_diagnostic_array(1, plan.diagnostics)),
  ]) +
  "\n"
}

///|
/// Render an audit as JSON.
///
/// The summary fields come first, then the collections. `changes` holds the
/// planned changes and `freezes` the change freezes, each sorted by start; the
/// remaining arrays keep the order the audit produced them in, so an overlap, a
/// conflict or an issue stays attributable to the same pair of records.
pub fn render_report_json(report : AuditReport) -> String {
  let overlap_elements : Array[String] = []
  for overlap in report.overlaps {
    overlap_elements.push(json_overlap_object(2, overlap))
  }
  let conflict_elements : Array[String] = []
  for conflict in report.freeze_conflicts {
    conflict_elements.push(json_conflict_object(2, conflict))
  }
  let issue_elements : Array[String] = []
  for issue in report.dependency_issues {
    issue_elements.push(json_issue_object(2, issue))
  }
  json_object(0, [
    json_field(1, "status", json_text(report.status())),
    json_field(
      1,
      "changes",
      json_window_array(1, sort_windows_by_start(report.plan.changes())),
    ),
    json_field(
      1,
      "freezes",
      json_window_array(1, sort_windows_by_start(report.plan.freezes())),
    ),
    json_field(1, "errors", report.error_count().to_string()),
    json_field(1, "warnings", report.warning_count().to_string()),
    json_field(1, "overlaps", json_array(1, overlap_elements)),
    json_field(1, "freeze_conflicts", json_array(1, conflict_elements)),
    json_field(1, "dependency_issues", json_array(1, issue_elements)),
    json_field(1, "blocked_minutes", report.blocked_minutes.to_string()),
    json_field(
      1,
      "diagnostics",
      json_diagnostic_array(1, report.plan.diagnostics),
    ),
  ]) +
  "\n"
}

///|
/// Render safe slots as a JSON array of `{start, end, minutes}` objects.
///
/// The input order is preserved: `safe_slots` already returns the intervals in
/// chronological order, and re-sorting here would hide a caller's own ordering.
pub fn render_slots_json(slots : Array[Slot]) -> String {
  let elements : Array[String] = []
  for slot in slots {
    elements.push(json_slot_object(1, slot))
  }
  json_array(0, elements) + "\n"
}
